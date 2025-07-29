provider "aws" {
  region  = var.region
  profile = var.profile
}

module "database" {
  source = "../../modules/database"

  name_prefix         = var.name_prefix
  vpc_id              = var.vpc_id
  database_subnet_ids = var.database_subnet_ids

  postgres_version      = var.postgres_version
  instance_class        = var.instance_class
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  multi_az              = var.multi_az

  database_name     = var.database_name
  database_username = var.database_username
  database_password = var.database_password

  maintenance_window      = var.maintenance_window
  backup_window           = var.backup_window
  backup_retention_period = var.backup_retention_period

  cluster_name              = var.cluster_name
  cluster_security_group_id = var.cluster_security_group_id
  node_security_group_id    = var.node_security_group_id

  tags = var.tags
}
