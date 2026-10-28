resource "aws_eks_cluster" "this" {
  name     = var.eks.cluster.name
  role_arn = data.aws_iam_role.cluster.arn
  version  = var.eks.cluster.kubernetes_version

  access_config {
    authentication_mode                         = var.eks.cluster.authentication_mode
    bootstrap_cluster_creator_admin_permissions = var.eks.cluster.bootstrap_cluster_creator_admin_permissions
  }

  encryption_config {
    provider {
      key_arn = aws_kms_key.secrets.arn
    }

    resources = ["secrets"]
  }

  vpc_config {
    subnet_ids              = [for key in concat(var.eks.cluster.public_subnet_keys, var.eks.cluster.private_subnet_keys) : var.subnet_ids[key]]
    security_group_ids      = [for key in var.eks.cluster.security_group_keys : var.security_group_ids[key]]
    endpoint_public_access  = var.eks.cluster.endpoint_public_access
    endpoint_private_access = var.eks.cluster.endpoint_private_access
  }

  tags = merge(var.eks.cluster.tags, {
    Name = var.eks.cluster.name
  })
}
