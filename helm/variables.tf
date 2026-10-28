variable "aws_region" {
  description = "AWS region containing the EKS cluster."
  type        = string
}

variable "eks_cluster_name" {
  description = "Name of the existing EKS cluster."
  type        = string
}

variable "helm" {
  description = "Helm releases managed after the EKS cluster is available."

  type = object({
    packages = map(object({
      name            = optional(string)
      enabled         = optional(bool, true)
      upgrade_install = optional(bool, false)
      repository      = string
      chart           = string
      version         = optional(string)
      namespace       = optional(string, "default")
      values          = optional(map(any), {})
    }))
  })
}
