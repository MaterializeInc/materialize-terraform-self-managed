module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.0"

  identifier = "${var.name_prefix}-db"

  engine               = "postgres"
  engine_version       = var.postgres_version
  family               = "postgres${var.postgres_version}"
  major_engine_version = var.postgres_version
  instance_class       = var.instance_class

  manage_master_user_password = false
  password                    = var.database_password

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_encrypted     = true

  db_name  = var.database_name
  username = var.database_username
  port     = 5432

  multi_az               = var.multi_az
  subnet_ids             = var.database_subnet_ids
  vpc_security_group_ids = [aws_security_group.database.id]
  create_db_subnet_group = true
  db_subnet_group_name   = "${var.name_prefix}-db-subnet"

  maintenance_window      = var.maintenance_window
  backup_window           = var.backup_window
  backup_retention_period = var.backup_retention_period
  skip_final_snapshot     = true

  tags = var.tags

  depends_on = [aws_security_group.database]
}

resource "aws_security_group" "database" {
  name_prefix = "${var.name_prefix}-sg-"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "eks_cluster_postgres_ingress" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.database.id
  source_security_group_id = var.cluster_security_group_id
  description              = "Allow PostgreSQL access from EKS cluster ${var.cluster_name}"
}

resource "aws_security_group_rule" "eks_nodes_postgres_ingress" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.database.id
  source_security_group_id = var.node_security_group_id
  description              = "Allow PostgreSQL access from EKS nodes ${var.cluster_name}"
}

resource "aws_security_group_rule" "allow_all_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.database.id
  description       = "Allow all outbound traffic"
}
