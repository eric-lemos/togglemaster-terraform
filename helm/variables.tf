variable "aws_region" {
  description = "AWS region containing the EKS cluster."
  type        = string
}

variable "eks_cluster_name" {
  description = "Name of the existing EKS cluster."
  type        = string
}

variable "self_healing_enabled" {
  description = "Enable Alertmanager notifications to the internal self-healing webhook."
  type        = bool
  default     = false
}

variable "helm" {
  description = "Helm releases managed after the EKS cluster is available."

  type = object({
    packages = any
  })
}
