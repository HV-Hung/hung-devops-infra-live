include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/resource-group.hcl"
  expose = true
}

# Inputs (resource_group_name, location, tags) are automatically inherited
# from root.hcl which reads the env.hcl file in this environment's directory.
