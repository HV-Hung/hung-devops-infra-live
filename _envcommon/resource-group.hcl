# ---------------------------------------------------------------------------------------------------------------------
# COMMON CONFIGURATION: Resource Group
# This file contains the shared Terragrunt configuration for the resource-group module.
# It is included by each environment's resource-group/terragrunt.hcl.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}//modules/resource-group"
}
