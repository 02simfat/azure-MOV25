# 1. Definiera variabler
$rgName     = "rg-novatrix-v35"
$location   = "swedencentral"
$vmName     = "vm-novatrix-web"
$adminUser  = "azureuser-web"
$cloudInit  = "./cloud-init.yaml"

# 2. Skapa resursgrupp
az group create --name $rgName --location $location

# 3. Skapa Virtuell Maskin
az vm create `
  --resource-group $rgName `
  --name $vmName `
  --image Ubuntu2404 `
  --admin-username $adminUser `
  --custom-data $cloudInit `
  --size Standard_B2ats_v2 `
  --os-disk-name "$vmName-osdisk" `
  --generate-ssh-keys `
  --public-ip-sku Standard

# 4. Öppna port 80 för webbtrafik
az vm open-port --resource-group $rgName --name $vmName --port 80 --priority 100

# 5. Hämta och visa IP-adressen
$publicIp = az vm show -d -g $rgName -n $vmName --query publicIps -o tsv
Write-Host "Klart! Surfa till: http://$publicIp/"