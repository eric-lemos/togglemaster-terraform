data "aws_iam_role" "cluster" {
  name = var.eks.iam.cluster_role_name
}

data "aws_iam_role" "node" {
  name = var.eks.iam.node_role_name
}
