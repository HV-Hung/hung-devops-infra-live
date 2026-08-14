# Agent Instructions: Infrastructure as Code (IaC)

## 🎯 Context
Terragrunt and Terraform configurations for provisioning Microsoft Azure resources.

## 🏗️ Directory Rules
- `/modules/*`: Pure, reusable Terraform modules (`.tf`). No environment-specific values.
- `/environments/*`: Terragrunt configurations (`terragrunt.hcl` and `env.yaml`). No `.tf` files here.

## 💻 Code Standards
1. Always use the latest `azurerm` provider.
2. Naming Conventions: Lowercase with hyphens (e.g., `rg-hung-devops-dev-eus`).
3. Ensure every module has comprehensive `outputs.tf`.
