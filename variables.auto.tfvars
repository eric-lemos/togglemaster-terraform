# -------------------------------------------
# PROVIDER CONFIGS
# -------------------------------------------
provider_configs = {
  aws_region   = "us-east-1"
  project_name = "togglemaster"
  environment  = "dev"
}

# -------------------------------------------
# NETWORKING
# -------------------------------------------
networking = {
  vpc = {
    name       = "togglemaster-vpc"
    cidr_block = "10.0.0.0/21"
  }

  igw = {
    enabled = true
    name    = "togglemaster-igw"
  }

  subnet = {
    public-a = {
      name                    = "togglemaster-subnet-public-a"
      cidr_block              = "10.0.1.0/24"
      availability_zone       = "us-east-1a"
      type                    = "public"
      map_public_ip_on_launch = true
      tags = {
        "kubernetes.io/cluster/togglemaster-eks-cluster" = "shared"
        "kubernetes.io/role/elb"                         = "1"
      }
    }

    public-b = {
      name                    = "togglemaster-subnet-public-b"
      cidr_block              = "10.0.2.0/24"
      availability_zone       = "us-east-1b"
      type                    = "public"
      map_public_ip_on_launch = true
      tags = {
        "kubernetes.io/cluster/togglemaster-eks-cluster" = "shared"
        "kubernetes.io/role/elb"                         = "1"
      }
    }

    private-eks-a = {
      name              = "togglemaster-subnet-private-eks-a"
      cidr_block        = "10.0.3.0/24"
      availability_zone = "us-east-1a"
      type              = "private"
    }

    private-eks-b = {
      name              = "togglemaster-subnet-private-eks-b"
      cidr_block        = "10.0.4.0/24"
      availability_zone = "us-east-1b"
      type              = "private"
    }

    private-data-a = {
      name              = "togglemaster-subnet-private-data-a"
      cidr_block        = "10.0.5.0/24"
      availability_zone = "us-east-1a"
      type              = "private"
    }

    private-data-b = {
      name              = "togglemaster-subnet-private-data-b"
      cidr_block        = "10.0.6.0/24"
      availability_zone = "us-east-1b"
      type              = "private"
    }
  }

  natgw = {
    nat-a = {
      name        = "togglemaster-nat-a"
      subnet_name = "togglemaster-subnet-public-a"
    }

    nat-b = {
      name        = "togglemaster-nat-b"
      subnet_name = "togglemaster-subnet-public-b"
    }
  }

  rtb = {
    public = {
      name        = "togglemaster-rtb-public"
      subnet_keys = ["public-a", "public-b"]
      routes = [
        {
          cidr_block   = "0.0.0.0/0"
          gateway_name = "togglemaster-igw"
        }
      ]
    }

    private-a = {
      name        = "togglemaster-rtb-private-a"
      subnet_keys = ["private-eks-a", "private-data-a"]
      routes = [
        {
          cidr_block       = "0.0.0.0/0"
          nat_gateway_name = "togglemaster-nat-a"
        }
      ]
    }

    private-b = {
      name        = "togglemaster-rtb-private-b"
      subnet_keys = ["private-eks-b", "private-data-b"]
      routes = [
        {
          cidr_block       = "0.0.0.0/0"
          nat_gateway_name = "togglemaster-nat-b"
        }
      ]
    }
  }
}

# -------------------------------------------
# SECURITY GROUPS
# -------------------------------------------
security_groups = {
  groups = {
    eks-cluster = {
      name        = "togglemaster-eks-node-sg"
      description = "Security group for EKS cluster"

      ingress = [
        {
          description               = "Allow all traffic from itself"
          from_port                 = -1
          to_port                   = -1
          protocol                  = "-1"
          source_security_group_key = "eks-cluster"
        }
      ]

      egress = [
        {
          description = "Allow all outbound"
          from_port   = -1
          to_port     = -1
          protocol    = "-1"
          cidr_ipv4   = "0.0.0.0/0"
        }
      ]
    }

    rds = {
      name        = "togglemaster-rds-sg"
      description = "Security group for RDS"

      ingress = [
        {
          description               = "Allow PostgreSQL from EKS cluster SG"
          from_port                 = 5432
          to_port                   = 5432
          protocol                  = "tcp"
          source_security_group_key = "eks-cluster"
        }
      ]
    }

    redis = {
      name        = "togglemaster-redis-sg"
      description = "Security group for Redis"

      ingress = [
        {
          description               = "Allow Redis from EKS cluster SG"
          from_port                 = 6379
          to_port                   = 6379
          protocol                  = "tcp"
          source_security_group_key = "eks-cluster"
        }
      ]
    }
  }
}

# -------------------------------------------
# EKS
# -------------------------------------------
eks = {
  iam = {
    cluster_role_name = "LabRole"
    node_role_name    = "LabRole"
  }

  cluster = {
    name                                        = "togglemaster-eks-cluster"
    kubernetes_version                          = "1.36"
    public_subnet_keys                          = ["public-a", "public-b"]
    private_subnet_keys                         = ["private-eks-a", "private-eks-b", "private-data-a", "private-data-b"]
    endpoint_public_access                      = true
    endpoint_private_access                     = false
    bootstrap_cluster_creator_admin_permissions = true
  }

  node_groups = {
    ng1 = {
      name                = "togglemaster-eks-ng1"
      security_group_keys = ["eks-cluster"]
      min_size            = 1
      max_size            = 4
      desired_size        = 2
      ami_type            = "AL2023_x86_64_STANDARD"
      instance_types      = ["t3.medium"]
      disk_size           = 20
    }
  }
}

# -------------------------------------------
# RDS
# -------------------------------------------
rds = {
  subnet_group = {
    name        = "togglemaster-rds-subnet-group"
    subnet_keys = ["private-data-a", "private-data-b"]
  }

  instances = {
    auth = {
      identifier          = "togglemaster-auth"
      username            = "auth_admin"
      security_group_keys = ["rds"]
    }

    flags = {
      identifier          = "togglemaster-flags"
      username            = "flags_admin"
      security_group_keys = ["rds"]
    }

    targeting = {
      identifier          = "togglemaster-targeting"
      username            = "targeting_admin"
      security_group_keys = ["rds"]
    }
  }
}

# -------------------------------------------
# ElastiCache
# -------------------------------------------
elasticache = {
  subnet_group = {
    name        = "togglemaster-elasticache-subnet-group"
    subnet_keys = ["private-data-a", "private-data-b"]
  }

  clusters = {
    redis = {
      name                = "togglemaster-redis"
      engine              = "redis"
      engine_version      = "7.1"
      node_type           = "cache.t3.micro"
      port                = 6379
      security_group_keys = ["redis"]
    }
  }
}

# -------------------------------------------
# DynamoDB
# -------------------------------------------
dynamodb = {
  tables = {
    analytics = {
      name                           = "ToggleMasterAnalytics"
      hash_key                       = "event_id"
      hash_key_type                  = "S"
      billing_mode                   = "PAY_PER_REQUEST"
      point_in_time_recovery_enabled = true
      server_side_encryption_enabled = true
    }
  }
}

# -------------------------------------------
# SQS
# -------------------------------------------
sqs = {
  queues = {
    analytics_events = {
      name                       = "togglemaster-analytics-events"
      visibility_timeout_seconds = 60
      message_retention_seconds  = 86400
      sqs_managed_sse_enabled    = true
    }
  }
}

# -------------------------------------------
# ECR
# -------------------------------------------
ecr = {
  repositories = {
    auth = {
      name = "togglemaster/auth"
    }

    analytics = {
      name = "togglemaster/analytics"
    }

    evaluation = {
      name = "togglemaster/evaluation"
    }

    flag = {
      name = "togglemaster/flag"
    }

    targeting = {
      name = "togglemaster/targeting"
    }
  }
}
