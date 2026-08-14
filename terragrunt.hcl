# ---------------------------------------------------------------------------------------------------------------------
# ROOT TERRAGRUNT CONFIGURATION
# This file generates the provider and remote state configurations dynamically.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # Automatically load environment-level variables from env.yaml
  env_vars = read_terragrunt_config(find_in_parent_folders("env.yaml"))
  env      = local.env_vars.locals.environment
}

# Generate an Azure provider block using OIDC for GitHub Actions compatibility
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "azurerm" {
  features {}
  use_oidc = true
}
EOF
}

# Configure remote state in the Storage Account created by bootstrap.sh
remote_state {
  backend = "azurerm"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    resource_group_name  = "rg-hung-devops-tfstate"
    storage_account_name = "sthungdevopstfstate"
    container_name       = "tfstate"
    # This dynamically creates a state file path matching the folder structure (e.g., dev/network/terraform.tfstate)
    key                  = "$${path_relative_to_include()}/terraform.tfstate"
    use_oidc             = true
  }
}

# Pass the environment variables down to all Terraform modules
inputs = merge(
  local.env_vars.locals,
  {
    tags = {
      project     = "hung-devops"
      environment = local.env
      managed_by  = "terragrunt"
    }
  }
)
