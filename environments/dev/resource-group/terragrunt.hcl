include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../modules/resource-group"
}

# Note: Inputs (resource_group_name, location, tags) are automatically inherited 
# from the root terragrunt.hcl which reads the dev/env.yaml file.
