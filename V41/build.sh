#!/bin/bash
# build.sh - bygger Nordviks hyresgastportal med felanmalan (V41)
#
#   ARM-templaten (arm/azuredeploy.json) -> natverk, NSG och saker lagring
#   Azure CLI (det har skriptet)         -> scale set, lastbalanserare,
#                                           roller och autoskalning
#
# Kor i Git Bash fran mappen V41:
#   bash build.sh          bygger driftmiljon  i rg-nordvik
#   bash build.sh test     bygger testmiljon   i rg-nordvik-test
#
# Kraver: az login, flow-url.txt (committas ALDRIG) och cloud-init.txt.
# Skriptet gar att kora flera ganger. Det som redan finns hoppas over.
# ==========================================================================
set -e                      # avbryt direkt om ett kommando misslyckas
export MSYS_NO_PATHCONV=1   # Git Bash: skriv inte om /subscriptions/... till C:/...

# --- Variabler: det som skiljer miljoerna at --------------------------------
MILJO="${1:-prod}"
case "$MILJO" in
  prod) RG="rg-nordvik" ;;
  test) RG="rg-nordvik-test" ;;
  *) echo "Okand miljo: $MILJO. Anvand: bash build.sh  eller  bash build.sh test"; exit 1 ;;
esac

LOCATION="swedencentral"
PARAMS="arm/parametrar.$MILJO.json"   # storage-namn, SKU och taggar per miljo
VMSS="vmss-nordvik-web"
NSG="nsg-nordvik-web"      # skapas av ARM-templaten. Anvands aven pa natverkskorten.
LB="lb-nordvik-web"
PIP="pip-nordvik-web"
BEPOOL="bepool-nordvik-web"
# Storlekar i turordning. Azure har ibland slut pa kapacitet for en storlek
# (felet SkuNotAvailable). Da provar skriptet nasta. Alla ar sma B-storlekar.
#   B1s    1 vCPU, 1 GB  ingar i gratiskvoten
#   B1ms   1 vCPU, 2 GB
#   B2ats_v2  2 vCPU, 1 GB  ingar i gratiskvoten (samma som i 18B)
#   B2ts_v2   2 vCPU, 1 GB  (samma som i V39)
STORLEKAR="Standard_B1s Standard_B1ms Standard_B2ats_v2 Standard_B2ts_v2"
INSTANSER=2                # minst 2: portalen ska tala att en instans faller bort
ZONER="1 2"                # sprid instanserna over tva datahallar (provas forst)
TAGGAR="foretag=Nordvik projekt=hyresgastportal avdelning=Forvaltning fastighet=Gemensam miljo=$MILJO"

# Hjalpfunktion: Git Bash pa Windows kan fa med \r i svar fran az. tr tar bort det.
fraga() { "$@" | tr -d '\r'; }

# Hjalpfunktion: rolltilldelning med omforsok. En ny identitet eller grupp
# kan ta en stund innan den syns overallt i Entra ID.
roll() { # $1=objekt-id  $2=typ (User/Group/ServicePrincipal)  $3=roll  $4=scope
  local fel
  for i in 1 2 3 4 5; do
    if fel=$(az role assignment create --assignee-object-id "$1" --assignee-principal-type "$2" \
         --role "$3" --scope "$4" -o none 2>&1); then
      echo "  OK: $3"
      return 0
    fi
    echo "  Vantar 15 s innan nytt forsok ($i av 5): $3"
    sleep 15
  done
  echo "  FEL: kunde inte ge rollen $3. Senaste felet fran Azure:"
  echo "$fel"
  return 1
}

echo "=== 0. Kontroll: konto, prenumeration och filer ==="
az account show --query "{konto:user.name, prenumeration:name}" -o table
for fil in arm/azuredeploy.json "$PARAMS" cloud-init.txt; do
  [ -f "$fil" ] || { echo "Saknar $fil. Kor skriptet fran mappen V41."; exit 1; }
done

# Hemligheten: flodets URL innehaller en signatur (sig=) och fungerar som ett losenord.
if [ ! -s flow-url.txt ]; then
  echo "Saknar flow-url.txt. Klistra in flodets HTTP-URL i den filen och kor igen."
  exit 1
fi
FLOW_URL=$(tr -d '\r\n' < flow-url.txt)

echo "=== 1. Resursgrupp $RG med taggar ==="
az group create --name "$RG" --location "$LOCATION" --tags $TAGGAR -o none

# Min publika IP far SSH och kan se lagringen i portalen. Ingen annan.
MY_IP=$(curl -s --max-time 10 https://api.ipify.org || true)
echo "Din publika IP: ${MY_IP:-okand (ingen admin-oppning)}"

echo "=== 2. ARM: natverk, NSG och lagring ==="
az deployment group validate -g "$RG" \
  --template-file arm/azuredeploy.json --parameters "@$PARAMS" adminIp="$MY_IP" -o none
az deployment group create -g "$RG" -n nordvik-infra \
  --template-file arm/azuredeploy.json --parameters "@$PARAMS" adminIp="$MY_IP" -o none

# Las ut vardena som templaten skapade (en kalla till sanning: parameterfilen)
utdata() { fraga az deployment group show -g "$RG" -n nordvik-infra --query "properties.outputs.$1.value" -o tsv; }
STORAGE=$(utdata storageName)
STORAGE_ID=$(utdata storageId)
CONTAINER_ID=$(utdata felanmalningarId)
SUBNET_ID=$(utdata subnetId)
if [ -z "$STORAGE" ] || [ -z "$CONTAINER_ID" ] || [ -z "$SUBNET_ID" ]; then
  echo "FEL: kunde inte lasa utdata fran ARM-deployen nordvik-infra."; exit 1
fi
echo "Lagring: $STORAGE"

echo "=== 3. Fyll i cloud-init (lokal kopia, committas aldrig) ==="
# sed-raden escapar tecken (& | \) som annars har specialbetydelse i sed.
FLOW_URL_ESC=$(printf '%s' "$FLOW_URL" | sed -e 's/[\\&|]/\\&/g')
sed -e "s|stnordvikXXXX|$STORAGE|" \
    -e "s|FLOW_URL = \"\"|FLOW_URL = \"$FLOW_URL_ESC\"|" \
    cloud-init.txt > cloud-init.generated.txt
if grep -q "stnordvikXXXX" cloud-init.generated.txt || grep -q 'FLOW_URL = ""' cloud-init.generated.txt; then
  echo "FEL: platshallarna i cloud-init.generated.txt fylldes inte i."; exit 1
fi

echo "=== 4. Scale set med $INSTANSER instanser bakom en lastbalanserare ==="
skapa_vmss() { # $1=storlek, resten=extra argument (t.ex. --zones 1 2)
  local storlek="$1"; shift
  az vmss create -g "$RG" -n "$VMSS" \
    --orchestration-mode Uniform \
    --image Ubuntu2204 --vm-sku "$storlek" --instance-count "$INSTANSER" "$@" \
    --subnet "$SUBNET_ID" --nsg "$NSG" \
    --lb "$LB" --lb-sku Standard --backend-pool-name "$BEPOOL" --public-ip-address "$PIP" \
    --upgrade-policy-mode Manual \
    --admin-username azureuser --generate-ssh-keys \
    --assign-identity \
    --custom-data cloud-init.generated.txt \
    --tags $TAGGAR -o none
}
visa_fel() { # visar bara det innersta felet (sista Code/Message), inte hela tracebacken
  echo "$1" | grep -E "^\s*(Code|Message):" | tail -2 | cut -c1-220 | sed 's/^ */      /'
}

if az vmss show -g "$RG" -n "$VMSS" -o none 2>/dev/null; then
  echo "  $VMSS finns redan, hoppar over."
  VM_SIZE=$(fraga az vmss show -g "$RG" -n "$VMSS" --query sku.name -o tsv)
else
  VM_SIZE=""
  for storlek in $STORLEKAR; do
    echo "  Provar $storlek i zon $ZONER ..."
    if svar=$(skapa_vmss "$storlek" --zones $ZONER 2>&1); then
      VM_SIZE="$storlek"; echo "  OK: $storlek i zon $ZONER"; break
    fi
    visa_fel "$svar"
    echo "  Provar $storlek utan zoner ..."
    if svar=$(skapa_vmss "$storlek" 2>&1); then
      VM_SIZE="$storlek"; echo "  OK: $storlek utan zoner"; break
    fi
    visa_fel "$svar"
  done
  if [ -z "$VM_SIZE" ]; then
    echo "FEL: ingen av storlekarna gick att skapa. Las felkoderna ovan."
    echo "Kolla kvoten med: az vm list-usage -l $LOCATION -o table"
    exit 1
  fi
fi
echo "  Storlek: $VM_SIZE"

echo "=== 5. Lastbalanserare: halsokontroll och regel for port 80 ==="
# Halsokontrollen fragar /health pa varje instans. Svarar den inte tas den ur drift.
if ! az network lb probe show -g "$RG" --lb-name "$LB" -n probe-health -o none 2>/dev/null; then
  az network lb probe create -g "$RG" --lb-name "$LB" -n probe-health \
    --protocol Http --port 80 --path /health -o none
fi
# Finns det redan en regel for port 80? Nyare az CLI skapar regeln LBRule sjalv
# i az vmss create. Tva regler for samma port och pool ar inte tillatet
# (RulesUseSameBackendPortProtocolAndPool), sa vi ateranvander den.
REGEL=$(fraga az network lb rule list -g "$RG" --lb-name "$LB" --query '[?backendPort==`80`] | [0].name' -o tsv)
if [ -n "$REGEL" ]; then
  echo "  Regeln $REGEL for port 80 finns redan. Kopplar den till halsokontrollen."
  az network lb rule update -g "$RG" --lb-name "$LB" -n "$REGEL" --probe-name probe-health -o none
else
  FRONTEND=$(fraga az network lb frontend-ip list -g "$RG" --lb-name "$LB" --query "[0].name" -o tsv)
  # Har lastbalanseraren en utgaende regel (internet ut for apt/pip) maste regeln
  # for port 80 stanga av sin egen utgaende SNAT, annars blir det konflikt.
  UTGAENDE=$(fraga az network lb outbound-rule list -g "$RG" --lb-name "$LB" --query "length(@)" -o tsv)
  if [ "${UTGAENDE:-0}" -gt 0 ]; then SNAT_AV=true; else SNAT_AV=false; fi
  az network lb rule create -g "$RG" --lb-name "$LB" -n rule-http \
    --protocol Tcp --frontend-port 80 --backend-port 80 \
    --frontend-ip-name "$FRONTEND" --backend-pool-name "$BEPOOL" \
    --probe-name probe-health --disable-outbound-snat "$SNAT_AV" -o none
fi

echo "=== 6. IAM: hanterad identitet far skriva i containern felanmalningar ==="
# Scope = bara containern, inte hela kontot (least privilege). Inga nycklar i koden.
PRINCIPAL_ID=$(fraga az vmss show -g "$RG" -n "$VMSS" --query identity.principalId -o tsv)
roll "$PRINCIPAL_ID" ServicePrincipal "Storage Blob Data Contributor" "$CONTAINER_ID"

echo "=== 7. IAM: Nordviks roller som grupper i Entra ID ==="
grupp() { # skapar gruppen om den saknas och skriver ut dess id
  local id
  id=$(az ad group show --group "$1" --query id -o tsv 2>/dev/null | tr -d '\r') || true
  if [ -z "$id" ]; then
    id=$(fraga az ad group create --display-name "$1" --mail-nickname "$1" --description "$2" --query id -o tsv)
  fi
  echo "$id"
}
RG_ID=$(fraga az group show -n "$RG" --query id -o tsv)
FORVALTARE_ID=$(grupp grp-nordvik-forvaltare "Nordvik: hanterar felanmalningar")
EKONOMI_ID=$(grupp grp-nordvik-ekonomi "Nordvik: lasande insyn och kostnader")
grupp grp-nordvik-hyresgaster "Nordvik: hyresgaster, ingen direkt Azure-atkomst" > /dev/null

echo "Forvaltare: hanterar felanmalningar och ser miljon"
roll "$FORVALTARE_ID" Group "Storage Blob Data Contributor" "$CONTAINER_ID"
roll "$FORVALTARE_ID" Group "Reader" "$RG_ID"
echo "Ekonomi: lasande insyn och kostnader"
roll "$EKONOMI_ID" Group "Reader" "$RG_ID"
roll "$EKONOMI_ID" Group "Cost Management Reader" "$RG_ID"
echo "Hyresgaster: medvetet INGEN Azure-roll. Portalen skriver at dem med sin identitet."

echo "Admin (du): far lasa blobbar for att verifiera i portalen"
ME_ID=$(fraga az ad signed-in-user show --query id -o tsv)
roll "$ME_ID" User "Storage Blob Data Reader" "$STORAGE_ID"

echo "=== 8. Autoskalning: $INSTANSER instanser eller fler dagtid, 1 pa natten ==="
# Hur manga instanser ryms i prenumerationens vCPU-kvot? Gratiskrediten har en
# lag grans, sa max raknas ut i stallet for att gissas.
VCPU=$(fraga az vm list-skus -l "$LOCATION" --size "$VM_SIZE" \
  --query "[?name=='$VM_SIZE'] | [0].capabilities[?name=='vCPUs'] | [0].value" -o tsv)
KVOT=$(fraga az vm list-usage -l "$LOCATION" --query "[?name.value=='cores'] | [0].limit" -o tsv)
ANVANT=$(fraga az vm list-usage -l "$LOCATION" --query "[?name.value=='cores'] | [0].currentValue" -o tsv)
MAX=$INSTANSER
if [[ "$VCPU" =~ ^[0-9]+$ && "$KVOT" =~ ^[0-9]+$ && "$ANVANT" =~ ^[0-9]+$ ]] && [ "$VCPU" -gt 0 ]; then
  MAX=$(( INSTANSER + (KVOT - ANVANT) / VCPU ))   # nuvarande + det som far plats
  [ "$MAX" -gt 4 ] && MAX=4
  [ "$MAX" -lt "$INSTANSER" ] && MAX=$INSTANSER
fi
echo "  vCPU-kvot: $ANVANT av $KVOT anvands. $VM_SIZE har $VCPU vCPU. Max instanser: $MAX"
autoskala() {
  az monitor autoscale create -g "$RG" --resource "$VMSS" \
    --resource-type Microsoft.Compute/virtualMachineScaleSets \
    --name autoskala-nordvik --min-count "$INSTANSER" --max-count "$MAX" --count "$INSTANSER" -o none
  az monitor autoscale rule create -g "$RG" --autoscale-name autoskala-nordvik \
    --condition "Percentage CPU > 70 avg 5m" --scale out 1 -o none
  az monitor autoscale rule create -g "$RG" --autoscale-name autoskala-nordvik \
    --condition "Percentage CPU < 30 avg 5m" --scale in 1 -o none
  # Natt 00-06: nastan ingen trafik. 1 instans (inte 0) sa att en vattenlacka
  # klockan 03 anda kan anmalas.
  az monitor autoscale profile create -g "$RG" --autoscale-name autoskala-nordvik \
    --name natt --min-count 1 --count 1 --max-count 2 \
    --timezone "W. Europe Standard Time" --start 00:00 --end 06:00 \
    --recurrence week mon tue wed thu fri sat sun -o none
}
if az monitor autoscale show -g "$RG" -n autoskala-nordvik -o none 2>/dev/null; then
  echo "  autoskala-nordvik finns redan, hoppar over."
else
  autoskala && echo "  OK: autoskalning" || echo "  VARNING: autoskalningen misslyckades. Resten fungerar, kolla felet ovan."
fi

echo "=== 9. Verifiering: svarar portalen genom lastbalanseraren? ==="
IP=$(fraga az network public-ip show -g "$RG" -n "$PIP" --query ipAddress -o tsv)
echo "Vantar pa cloud-init (brukar ta 3-5 minuter)..."
for i in $(seq 1 30); do
  SVAR=$(curl -s --max-time 5 "http://$IP/health" || true)
  if echo "$SVAR" | grep -q '"status"'; then
    echo "  Svar: $SVAR"
    break
  fi
  sleep 20
done

echo "=========================================================="
echo " KLART ($MILJO)"
echo " Portalen:        http://$IP"
echo " Halsokontroll:   curl http://$IP/health   (kor flera ganger: instans varierar)"
echo " Resursgrupp:     $RG"
echo " Lagring:         $STORAGE (containern felanmalningar)"
echo " RBAC kan ta 1-2 minuter att sla igenom. Ett fel 503 i borjan ar normalt."
echo " Riv allt med:    bash destroy.sh $MILJO"
echo "=========================================================="
