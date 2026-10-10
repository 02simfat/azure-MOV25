#!/bin/bash
# destroy.sh - river Nordviks miljo (V41)
#
#   bash destroy.sh          river driftmiljon  rg-nordvik
#   bash destroy.sh test     river testmiljon   rg-nordvik-test
#
# Allt i resursgruppen forsvinner: scale set, lastbalanserare, natverk och
# lagring (med alla felanmalningar). Bygg upp igen med: bash build.sh
# ==========================================================================
set -e
export MSYS_NO_PATHCONV=1

MILJO="${1:-prod}"
case "$MILJO" in
  prod) RG="rg-nordvik" ;;
  test) RG="rg-nordvik-test" ;;
  *) echo "Okand miljo: $MILJO. Anvand: bash destroy.sh  eller  bash destroy.sh test"; exit 1 ;;
esac

echo "Raderar $RG och allt i den. Det tar nagra minuter i bakgrunden."
az group delete --name "$RG" --yes --no-wait

# Den ifyllda cloud-init-filen innehaller flodets URL. Ta bort den lokalt.
rm -f cloud-init.generated.txt

echo "Klart. Det har ligger kvar med flit:"
echo "  - Entra-grupperna grp-nordvik-* (kostar inget, ateranvands vid nasta bygge)"
echo "  - Budgetlarmet budget-nordvik (ligger pa prenumerationen)"
echo "Kolla att gruppen ar borta: az group exists --name $RG"
