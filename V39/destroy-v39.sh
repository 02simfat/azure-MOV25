#!/bin/bash
# destroy-v39.sh - river hela V39-miljon i Azure (resursgruppen och allt i den).
# Flodet i Power Automate och SharePoint-listan paverkas inte.
RG="rg-novatrix-v39"
az group delete --name "$RG" --yes --no-wait
echo "Borttagning av $RG startad (tar nagra minuter)."
