output "vpc_id" {
  value = module.networking.vpc_id
}

output "vpc_cidr_block" {
  value = module.networking.vpc_cidr_block
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}
