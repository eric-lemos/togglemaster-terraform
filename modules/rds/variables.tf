variable "rds" {
  description = "RDS configuration (subnet group and DB instances). Subnet ids and security group ids are wired from other modules' outputs."

  type = object({
    subnet_group = object({
      name        = optional(string)
      subnet_keys = list(string)
    })

    # Map key = logical DB instance identifier (e.g. "flags", "targeting")
    instances = map(object({
      identifier                   = optional(string)
      engine                       = optional(string, "postgres")
      engine_version               = optional(string)
      instance_class               = optional(string, "db.t3.micro")
      allocated_storage            = optional(number, 20)
      storage_encrypted            = optional(bool, true)
      db_name                      = optional(string, "postgres")
      username                     = string
      security_group_keys          = optional(list(string), [])
      publicly_accessible          = optional(bool, false)
      skip_final_snapshot          = optional(bool, true)
      multi_az                     = optional(bool, false)
      backup_retention_period      = optional(number, 7)
      monitoring_interval          = optional(number, 0)   # 0 disables Enhanced Monitoring (avoids extra cost)
      performance_insights_enabled = optional(bool, false) # disabled by default (avoids extra cost)
      tags                         = optional(map(string), {})
    }))

    tags = optional(map(string), {})
  })

  validation {
    condition     = length(var.rds.subnet_group.subnet_keys) > 0
    error_message = "rds.subnet_group must provide at least one subnet key."
  }

  validation {
    condition = alltrue([
      for k, i in var.rds.instances :
      can(regex("^[A-Za-z][A-Za-z0-9-]{0,62}$", coalesce(i.identifier, k)))
    ])
    error_message = "rds.instances.*.identifier must start with a letter and contain only letters, numbers or hyphens (up to 63 characters)."
  }

  validation {
    condition = alltrue([
      for k, i in var.rds.instances :
      can(regex("^[A-Za-z][A-Za-z0-9]*$", i.db_name))
    ])
    error_message = "rds.instances.*.db_name must start with a letter and contain only alphanumeric characters."
  }
}

variable "passwords" {
  description = "Master user passwords indexed by RDS instance key."
  type        = map(string)
  sensitive   = true

  validation {
    condition     = alltrue([for key in keys(var.rds.instances) : contains(keys(var.passwords), key)])
    error_message = "passwords must provide a password for every key defined in rds.instances."
  }
}

variable "subnet_ids" {
  description = "Subnet IDs indexed by logical subnet key."
  type        = map(string)
}

variable "security_group_ids" {
  description = "Security group IDs indexed by logical security group key."
  type        = map(string)
}
