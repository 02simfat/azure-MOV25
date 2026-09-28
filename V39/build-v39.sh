#!/bin/bash
# build-v39.sh - reser Azure-delen av Novatrix kedja i V39
#
#   Formular pa webb-VM - app.py sparar arendet som blob (hanterad identitet)
#                     - app.py skickar arendet till Power Automate (FLOW_URL)
#
# Kor i Git Bash fran mappen V39:   bash build-v39.sh
# Kraver: az login med kontot som ager Azure-prenumerationen (gmail-kontot)
#         och filen flow-url.txt med flodets HTTP-URL (committas ALDRIG).
# ==========================================================================
set -e                      # avbryt direkt om ett kommando misslyckas 
export MSYS_NO_PATHCONV=1   # Git Bash: skriv inte om /subscriptions/... till C:/...

#  Variabler (det som varierar mellan miljoer) 
RG="rg-novatrix-v39"
LOCATION="swedencentral"
VNET="vnet-novatrix"
SUBNET="snet-web"
NSG="nsg-web"
VM="vm-novatrix-web"
VM_SIZE="Standard_B2ts_v2"
STORAGE="stnovatrixsimon2"   # maste vara globalt unikt, sma bokstaver och siffror
CONTAINER="arenden"

echo "=== 0. Kontroll: vilket konto och vilken prenumeration anvands? ==="
az account show --query "{konto:user.name, prenumeration:name}" -o table

#  Hemligheten: flodets URL 
# URL:en innehaller en signatur (sig=...) och fungerar som ett losenord.
# Den ligger i en lokal fil som .gitignore stoppar fran att hamna i repot.
if [ ! -s flow-url.txt ]; then
  echo "Saknar flow-url.txt. Klistra in flodets HTTP-URL i den filen och kor igen."
  exit 1
fi
FLOW_URL=$(tr -d '\r\n' < flow-url.txt)

# Bygg en cloud-init med ratt kontonamn och URL 
# cloud-init.txt i repot har platshallare. Den ifyllda kopian ignoreras av git.
# sed-raden escapar tecken (& | \) som annars har specialbetydelse i sed.
FLOW_URL_ESC=$(printf '%s' "$FLOW_URL" | sed -e 's/[\\&|]/\\&/g')
sed -e "s|stnovatrixXXXX|$STORAGE|" \
    -e "s|FLOW_URL = \"\"|FLOW_URL = \"$FLOW_URL_ESC\"|" \
    cloud-init.txt > cloud-init.generated.txt

echo "=== 1. Resursgrupp ==="
az group create --name "$RG" --location "$LOCATION" -o none

echo "=== 2. Natverk: VNet, subnat och NSG ==="
az network vnet create --resource-group "$RG" --name "$VNET" \
  --address-prefixes 10.0.0.0/16 \
  --subnet-name "$SUBNET" --subnet-prefixes 10.0.1.0/24 -o none

az network nsg create --resource-group "$RG" --name "$NSG" -o none

# Webbtrafik fran alla (formularet ska vara publikt)
az network nsg rule create --resource-group "$RG" --nsg-name "$NSG" \
  --name allow-http --priority 100 --protocol Tcp \
  --destination-port-ranges 80 --access Allow -o none

# SSH bara fran min egen publika IP (least privilege)
MY_IP=$(curl -s https://api.ipify.org || true)
if [ -z "$MY_IP" ]; then
  echo "Kunde inte hamta din IP. SSH-regeln hoppas over (anvand az vm run-command vid behov)."
else
  az network nsg rule create --resource-group "$RG" --nsg-name "$NSG" \
    --name allow-ssh-my-ip --priority 110 --protocol Tcp \
    --destination-port-ranges 22 --source-address-prefixes "$MY_IP" \
    --access Allow -o none
fi

az network vnet subnet update --resource-group "$RG" --vnet-name "$VNET" \
  --name "$SUBNET" --network-security-group "$NSG" -o none

echo "=== 3. Lagring: konto och container $CONTAINER ==="
az storage account create --resource-group "$RG" --name "$STORAGE" \
  --location "$LOCATION" --sku Standard_LRS --kind StorageV2 \
  --min-tls-version TLS1_2 --allow-blob-public-access false -o none

# container-rm gar via Azure Resource Manager, sa inget datarolls-krav pa mitt konto
az storage container-rm create --resource-group "$RG" \
  --storage-account "$STORAGE" --name "$CONTAINER" -o none

STORAGE_ID=$(az storage account show --resource-group "$RG" --name "$STORAGE" --query id -o tsv)

echo "=== 4. Webb-VM med system-tilldelad identitet och cloud-init ==="
az vm create --resource-group "$RG" --name "$VM" \
  --image Ubuntu2204 --size "$VM_SIZE" \
  --vnet-name "$VNET" --subnet "$SUBNET" --nsg "" \
  --admin-username azureuser --generate-ssh-keys \
  --assign-identity \
  --custom-data cloud-init.generated.txt -o none

echo "=== 5. RBAC: VM:ens identitet far skriva blobbar (inga nycklar i koden) ==="
PRINCIPAL_ID=$(az vm show --resource-group "$RG" --name "$VM" --query identity.principalId -o tsv)
for i in 1 2 3 4 5; do
  az role assignment create \
    --assignee-object-id "$PRINCIPAL_ID" --assignee-principal-type ServicePrincipal \
    --role "Storage Blob Data Contributor" --scope "$STORAGE_ID" -o none && break
  echo "Identiteten ar inte klar an, vantar 15 sekunder (forsok $i av 5)..."
  sleep 15
done

IP=$(az vm show -d --resource-group "$RG" --name "$VM" --query publicIps -o tsv)

echo "=========================================================="
echo " KLART. Vanta 2-3 minuter medan cloud-init installerar appen."
echo " Formularet:  http://$IP"
echo " Halsokontroll:  ssh azureuser@$IP \"curl -s localhost:5000/health\""
echo " Rollen kan ta 1-2 minuter att sla igenom (403 i borjan ar normalt)."
echo "=========================================================="
