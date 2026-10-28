variable "eks" {
  description = "EKS configuration (cluster, IAM role references and managed node groups)."

  type = object({
    cluster = object({
      name                                        = string
      kubernetes_version                          = optional(string, "1.33")
      public_subnet_keys                          = optional(list(string), [])
      private_subnet_keys                         = optional(list(string), [])
      security_group_keys                         = optional(list(string), [])
      endpoint_public_access                      = optional(bool, true)
      endpoint_private_access                     = optional(bool, true)
      authentication_mode                         = optional(string, "API_AND_CONFIG_MAP")
      bootstrap_cluster_creator_admin_permissions = optional(bool, true)
      tags                                        = optional(map(string), {})
    })

    iam = object({
      cluster_role_name = string
      node_role_name    = string
    })

    node_groups = optional(map(object({
      name                = optional(string)
      subnet_keys         = optional(list(string), [])
      security_group_keys = optional(list(string), [])
      min_size            = optional(number, 1)
      max_size            = optional(number, 4)
      desired_size        = optional(number, 2)
      ami_type            = optional(string, "AL2023_x86_64_STANDARD")
      instance_types      = optional(list(string), ["t3.medium"])
      disk_size           = optional(number, 20)
      tags                = optional(map(string), {})
    })), {})
  })

  validation {
    condition = (
      length(var.eks.cluster.public_subnet_keys) + length(var.eks.cluster.private_subnet_keys)
    ) > 0
    error_message = "eks.cluster must provide at least one subnet key."
  }

  validation {
    condition     = contains(["API", "API_AND_CONFIG_MAP", "CONFIG_MAP"], var.eks.cluster.authentication_mode)
    error_message = "eks.cluster.authentication_mode must be one of: API, API_AND_CONFIG_MAP or CONFIG_MAP."
  }

  validation {
    condition = alltrue([
      for k, ng in var.eks.node_groups :
      ng.min_size <= ng.desired_size && ng.desired_size <= ng.max_size
    ])
    error_message = "eks.node_groups.* requires min_size <= desired_size <= max_size."
  }

  validation {
    condition = alltrue([
      for k, ng in var.eks.node_groups :
      length(ng.subnet_keys) > 0 || length(var.eks.cluster.private_subnet_keys) > 0
    ])
    error_message = "Each node group must provide subnet_keys or the cluster must provide private_subnet_keys."
  }
}

variable "vpc_id" {
  description = "VPC ID for the EKS cluster."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs indexed by logical subnet key."
  type        = map(string)
}

variable "security_group_ids" {
  description = "Security group IDs indexed by logical security group key."
  type        = map(string)
}
