#!/bin/bash
# ==============================================================================
# Bootstrap: Azure Terraform State & GitHub Actions Identity
# This script creates the foundational Azure resources needed for Terragrunt.
# ==============================================================================

# Variables (Update these if necessary)
LOCATION="eastus"
RG_NAME="rg-hung-devops-tfstate"
SA_NAME="sthungdevopstfstate" # Must be globally unique, lowercase, no dashes
CONTAINER_NAME="tfstate"
IDENTITY_NAME="id-github-actions-iac"
GITHUB_ORG="HV-Hung"
GITHUB_REPO="hung-devops-infra-live"

echo "1. Creating Resource Group..."
az group create --name $RG_NAME --location $LOCATION

echo "2. Creating Storage Account for Terraform State..."
az storage account create --name $SA_NAME --resource-group $RG_NAME \
  --location $LOCATION --sku Standard_LRS --encryption-services blob

echo "3. Creating Blob Container..."
az storage container create --name $CONTAINER_NAME --account-name $SA_NAME \
  --auth-mode login

echo "4. Creating Managed Identity for GitHub Actions..."
az identity create --name $IDENTITY_NAME --resource-group $RG_NAME

# Get Identity Client ID and Principal ID
IDENTITY_CLIENT_ID=$(az identity show --name $IDENTITY_NAME --resource-group $RG_NAME --query 'clientId' -o tsv)
IDENTITY_PRINCIPAL_ID=$(az identity show --name $IDENTITY_NAME --resource-group $RG_NAME --query 'principalId' -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

echo "5. Assigning Contributor Role to the Identity for the Subscription..."
# Note: In a production environment, scope this to specific Resource Groups rather than the whole Subscription.
az role assignment create --assignee $IDENTITY_PRINCIPAL_ID \
  --role "Contributor" --scope "/subscriptions/$SUBSCRIPTION_ID"

echo "6. Creating Federated Identity Credential for GitHub Actions (Main Branch)..."
az identity federated-credential create --name "github-actions-main" \
  --identity-name $IDENTITY_NAME --resource-group $RG_NAME \
  --issuer "https://token.actions.githubusercontent.com" \
  --subject "repo:$GITHUB_ORG/$GITHUB_REPO:ref:refs/heads/main" \
  --audiences "api://AzureADTokenExchange"

TENANT_ID=$(az account show --query tenantId -o tsv)

echo "7. Configuring GitHub Secrets for Actions OIDC..."
if command -v gh &> /dev/null; then
    echo "Pushing secrets to $GITHUB_ORG/$GITHUB_REPO..."
    gh secret set AZURE_CLIENT_ID --body "$IDENTITY_CLIENT_ID" --repo "$GITHUB_ORG/$GITHUB_REPO"
    gh secret set AZURE_TENANT_ID --body "$TENANT_ID" --repo "$GITHUB_ORG/$GITHUB_REPO"
    gh secret set AZURE_SUBSCRIPTION_ID --body "$SUBSCRIPTION_ID" --repo "$GITHUB_ORG/$GITHUB_REPO"
    echo "✅ GitHub secrets successfully configured!"
else
    echo "⚠️ WARNING: GitHub CLI (gh) is not installed or not in PATH."
    echo "Please manually add AZURE_CLIENT_ID, AZURE_TENANT_ID, and AZURE_SUBSCRIPTION_ID to your repository secrets."
fi

echo "====================================================================="
echo "Setup Complete! Save these values for your terragrunt.hcl & GitHub:"
echo "Storage Account: $SA_NAME"
echo "Container: $CONTAINER_NAME"
echo "Resource Group: $RG_NAME"
echo "Identity Client ID (ARM_CLIENT_ID): $IDENTITY_CLIENT_ID"
echo "Subscription ID (ARM_SUBSCRIPTION_ID): $SUBSCRIPTION_ID"
echo "Tenant ID (ARM_TENANT_ID): $TENANT_ID"
echo "====================================================================="
