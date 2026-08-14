# Hung DevOps: Infrastructure as Code (IaC) 🏗️

This repository manages the Azure infrastructure for Hung DevOps using **Terraform** and **Terragrunt** to ensure DRY code across environments (Dev, QA, Prod).

## 🚀 Getting Started (Local Setup)

To execute this IaC locally or via GitHub Actions, you first need to bootstrap the remote state storage and OIDC Managed Identity.

1. Install [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) and [Terragrunt](https://terragrunt.gruntwork.io/).
2. Login to Azure: `az login`
3. Edit the `setup/bootstrap.sh` script to include your GitHub Username in the `GITHUB_ORG` variable.
4. Run the bootstrap script:
   ```bash
   cd setup
   bash bootstrap.sh
   ```
