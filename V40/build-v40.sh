#!/bin/bash
# build-v40.sh - kor Novatrix kundtjanstsida som en container i Azure (V40)
#
#   Dockerfile -> image (GitHub Actions bygger) -> ghcr.io (lagra) -> container i ACI (kora)
#   ...och sist verifierar skriptet att sidan svarar.
#
# Ordning:
#   1. git push         -> GitHub Actions bygger imagen och lagrar den pa ghcr.io
#   2. Paketet novatrix-web gors Public pa GitHub (en gang)
#   3. bash build-v40.sh -> det har skriptet startar containern i Azure
#
# Kor i Git Bash fran mappen V40:   bash build-v40.sh
# Kraver: az login med kontot som ager Azure-prenumerationen.
# Inga losenord behovs: imagen ar publik och innehaller bara en publik webbsida.
# ==========================================================================
set -e                         # avbryt direkt om ett kommando misslyckas
export MSYS_NO_PATHCONV=1      # Git Bash: skriv inte om /subscriptions/... till C:/...
cd "$(dirname "$0")"           # stall dig i V40

#  Variabler (det som varierar mellan miljoer)
RG="rg-novatrix-v40"
LOCATION="swedencentral"
IMAGE_REPO="02simfat/novatrix-web"   # agare/namn pa ghcr.io, bara sma bokstaver
IMAGE_TAG="v1"                       # version, inte latest
IMAGE="ghcr.io/$IMAGE_REPO:$IMAGE_TAG"
ACI="aci-novatrix-web"
DNS_LABEL="novatrix-simon-v40"       # ger adressen <label>.swedencentral.azurecontainer.io

echo "=== 0. Kontroll: vilket konto och vilken prenumeration anvands? ==="
az account show --query "{konto:user.name, prenumeration:name}" -o table

echo "=== 1. Kontroll: finns imagen pa ghcr.io och ar den publik? ==="
# Vi gor som ACI: ber om en anonym token och fragar efter imagen.
# Svar 200 = imagen finns och far hamtas utan losenord. Kollas innan nagot skapas i Azure.
TOKEN=$(curl -s "https://ghcr.io/token?scope=repository:$IMAGE_REPO:pull" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json,application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json" \
  "https://ghcr.io/v2/$IMAGE_REPO/manifests/$IMAGE_TAG" || true)
if [ "$CODE" != "200" ]; then
  echo "Hittar inte $IMAGE (svar: $CODE)."
  echo "Kolla 1) att korningen under fliken Actions pa GitHub ar gron,"
  echo "      2) att paketet novatrix-web ar Public (Package settings -> Change visibility)."
  exit 1
fi
echo "  $IMAGE: finns och ar publik"

echo "=== 2. Resursleverantor (behovs en gang per prenumeration) ==="
# Utan registrering svarar Azure 'subscription is not registered' (lararen fick det i demon).
# tr -d '\r' tar bort Windows-radslut som annars gor att jamforelsen aldrig blir sann.
NS="Microsoft.ContainerInstance"
az provider register --namespace "$NS" -o none
until [ "$(az provider show --namespace "$NS" --query registrationState -o tsv | tr -d '\r')" = "Registered" ]; do
  echo "  $NS registreras, vantar 10 sekunder..."
  sleep 10
done
echo "  $NS: Registered"

echo "=== 3. Resursgrupp ==="
az group create --name "$RG" --location "$LOCATION" -o none

echo "=== 4. Kor imagen som en container i ACI ==="
# Imagen ar publik, sa ACI behover inget anvandarnamn eller losenord.
az container create --resource-group "$RG" --name "$ACI" \
  --image "$IMAGE" \
  --os-type Linux --cpu 1 --memory 1 \
  --ports 80 --ip-address Public --dns-name-label "$DNS_LABEL" -o none

echo "=== 5. Verifiera: kor containern och svarar sidan? ==="
az container show --resource-group "$RG" --name "$ACI" \
  --query "{status:instanceView.state, ip:ipAddress.ip, adress:ipAddress.fqdn}" -o table

IP=$(az container show --resource-group "$RG" --name "$ACI" --query ipAddress.ip -o tsv | tr -d '\r')
FQDN=$(az container show --resource-group "$RG" --name "$ACI" --query ipAddress.fqdn -o tsv | tr -d '\r')

CODE="000"
for i in 1 2 3 4 5 6; do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://$IP" || true)
  if [ "$CODE" = "200" ]; then break; fi
  echo "  Svar: $CODE, vantar 10 sekunder (forsok $i av 6)..."
  sleep 10
done

echo "=========================================================="
echo " HTTP-svar fran containern: $CODE  (200 = OK)"
echo " Sidan:  http://$FQDN"
echo "         http://$IP"
echo " Loggar: az container logs --resource-group $RG --name $ACI"
echo " Stada:  bash destroy-v40.sh  (ACI kostar per sekund den kor)"
echo "=========================================================="
