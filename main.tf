module "networking" {
  source     = "./modules/networking"
  networking = var.networking
}

module "security_group" {
  source          = "./modules/security_group"
  security_groups = var.security_groups
  vpc_id          = module.networking.vpc_id
}

module "eks" {
  source             = "./modules/eks"
  eks                = var.eks
  vpc_id             = module.networking.vpc_id
  subnet_ids         = module.networking.subnet_ids
  security_group_ids = module.security_group.security_group_ids
}

module "rds" {
  source             = "./modules/rds"
  rds                = var.rds
  passwords          = var.rds_instance_passwords
  subnet_ids         = module.networking.subnet_ids
  security_group_ids = module.security_group.security_group_ids
}

module "elasticache" {
  source             = "./modules/elasticache"
  elasticache        = var.elasticache
  subnet_ids         = module.networking.subnet_ids
  security_group_ids = module.security_group.security_group_ids
}

module "dynamodb" {
  source   = "./modules/dynamodb"
  dynamodb = var.dynamodb
}

module "sqs" {
  source = "./modules/sqs"
  sqs    = var.sqs
}

module "ecr" {
  source = "./modules/ecr"
  ecr    = var.ecr
}
