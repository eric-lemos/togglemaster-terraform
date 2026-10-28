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
    packages = any
  })
}
