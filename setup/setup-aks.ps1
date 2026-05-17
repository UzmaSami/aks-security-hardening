# ================================================
# AKS Security Hardening - Cluster Setup Script
# ================================================

# Variables - Change these to your own values
$ResourceGroup = "aks-security-rg"
$ClusterName   = "aks-security-cluster"
$Location      = "eastus"
$NodeCount     = 2

Write-Host "[*] Creating Resource Group..." -ForegroundColor Cyan
az group create `
    --name $ResourceGroup `
    --location $Location

Write-Host "[*] Creating AKS Cluster with security features..." -ForegroundColor Cyan
az aks create `
    --resource-group $ResourceGroup `
    --name $ClusterName `
    --node-count $NodeCount `
    --enable-addons monitoring,azure-policy `
    --network-plugin azure `
    --generate-ssh-keys

Write-Host "[*] Getting cluster credentials..." -ForegroundColor Cyan
az aks get-credentials `
    --resource-group $ResourceGroup `
    --name $ClusterName

Write-Host "[+] AKS Cluster created and configured!" -ForegroundColor Green
kubectl get nodes