```bash
az resource list -g rg-novatrix-v38 -o table                                                                                   
Name               ResourceGroup    Location       Type                               Status
-----------------  ---------------  -------------  ---------------------------------  ---------
stnovatrixsimon38  rg-novatrix-v38  swedencentral  Microsoft.Storage/storageAccounts  Succeeded
```

```powershell
 git log --oneline
dd79299 (HEAD -> main, origin/main, origin/HEAD) Lägger till privat subnät snet-db för framtida backend och lagring
dde4d31 Lägger till parameterfil för miljon
0c5ceb8 Lägger till NSG med webbregel för port 80 och 443
fb5e9bf Lägger till storage och VNet i miljo-skelett.json
2e32f57 Merge branch 'main' of https://github.com/02simfat/azure-MOV25
389a30d Lägger till startpaket i V38
```

```bash
git diff HEAD~1 HEAD -- miljo-skelett.json
diff --git a/V38/v38-startpaket/miljo-skelett.json b/V38/v38-startpaket/miljo-skelett.json
index 3f4781b..e948746 100644
--- a/V38/v38-startpaket/miljo-skelett.json
+++ b/V38/v38-startpaket/miljo-skelett.json
@@ -5,27 +5,34 @@
     "namePrefix": {
       "type": "string",
       "defaultValue": "novatrix",
-      "metadata": { "description": "Prefix for alla resursnamn, sa att allt hanger ihop." }
+      "metadata": {
+        "description": "Prefix for alla resursnamn, sa att allt hanger ihop."
+      }
     },
     "storageName": {
       "type": "string",
-      "metadata": { "description": "Globalt unikt namn, sma bokstaver och siffror." }
+      "metadata": {
+        "description": "Globalt unikt namn, sma bokstaver och siffror."
+      }
     },
```
```bash
"provisioningState": "Succeeded",
```
```
git clone https://github.com/02simfat/azure-MOV25.git test-klon
cd test-klon\V38\v38-startpaket
az group create --name rg-novatrix-v38-test --location swedencentral
az deployment group what-if -g rg-novatrix-v38-test --template-file miljo-skelett.json --parameters '@azuredeploy.parameters.json' storageName=stnovatrixsimon38test
az deployment group create -g rg-novatrix-v38-test --template-file miljo-skelett.json --parameters '@azuredeploy.parameters.json' storageName=stnovatrixsimon38test
az resource list -g rg-novatrix-v38-test -o table
```

Name                   ResourceGroup         Location       Type                                     Status
---------------------  --------------------  -------------  ---------------------------------------  ---------
novatrix-nsg           rg-novatrix-v38-test  swedencentral  Microsoft.Network/networkSecurityGroups  Succeeded
stnovatrixsimon38test  rg-novatrix-v38-test  swedencentral  Microsoft.Storage/storageAccounts        Succeeded
novatrix-vnet          rg-novatrix-v38-test  swedencentral  Microsoft.Network/virtualNetworks        Succeeded
```