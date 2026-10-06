#!/bin/bash
# destroy-v40.sh - river allt i Azure fran V40 i ett svep
# Tar bort resursgruppen med containern (ACI).
# Imagen ligger kvar pa ghcr.io (gratis for publika paket), sa build-v40.sh
# kan starta containern igen pa nagon minut.
#
# Kor i Git Bash fran mappen V40:   bash destroy-v40.sh
# ==========================================================================
set -e
RG="rg-novatrix-v40"

echo "Tar bort resursgruppen $RG (containern och allt annat i gruppen)..."
az group delete --name "$RG" --yes --no-wait

echo "Borttagningen ar startad och tar nagra minuter."
echo "Kontrollera med:  az group exists --name $RG   (false = borta)"
