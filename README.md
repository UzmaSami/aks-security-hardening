# Kubernetes Cluster Security Hardening (AKS)

## Overview
A comprehensive security hardening implementation for Azure Kubernetes
Service (AKS) covering RBAC, network policies, pod security, and
runtime threat monitoring.

## Security Controls Implemented
- ✅ RBAC - Role Based Access Control
- ✅ Network Policies - Default deny all traffic
- ✅ Pod Security - Non-root, read-only containers
- ✅ Secrets Management - Azure Key Vault integration
- ✅ Runtime Monitoring - Falco threat detection

## Technologies
- Azure Kubernetes Service (AKS)
- kubectl & Helm
- Azure CLI
- Falco Runtime Security
- Azure Key Vault

## How to Deploy
'''bash
az login
.\setup\setup-aks.ps1
kubectl apply -f rbac/
kubectl apply -f network-policies/
kubectl apply -f pod-security/
'''

## Author
Uzma Shabbir— Cloud Security Engineer
