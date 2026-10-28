data "aws_rds_engine_version" "postgres_16" {
  engine       = "postgres"
  version      = "16"
  latest       = true
  default_only = true
}

resource "aws_db_instance" "this" {
  for_each = var.rds.instances

  identifier     = coalesce(each.value.identifier, each.key)
  engine         = each.value.engine
  engine_version = coalesce(each.value.engine_version, data.aws_rds_engine_version.postgres_16.version)
  instance_class = each.value.instance_class

  allocated_storage = each.value.allocated_storage
  storage_encrypted = each.value.storage_encrypted

  db_name  = each.value.db_name
  username = each.value.username
  password = sensitive(var.passwords[each.key])

  db_subnet_group_name = aws_db_subnet_group.this.name

  vpc_security_group_ids = [for key in each.value.security_group_keys : var.security_group_ids[key]]

  multi_az                = each.value.multi_az
  backup_retention_period = each.value.backup_retention_period
  publicly_accessible     = each.value.publicly_accessible
  skip_final_snapshot     = each.value.skip_final_snapshot

  monitoring_interval          = each.value.monitoring_interval
  performance_insights_enabled = each.value.performance_insights_enabled

  tags = merge(var.rds.tags, each.value.tags, {
    Name = coalesce(each.value.identifier, each.key)
  })
}
