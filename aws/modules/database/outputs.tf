output "db_instance_endpoint" {
  description = "The connection endpoint for the RDS instance"
  value       = module.db.db_instance_endpoint
}

output "db_instance_id" {
  description = "The RDS instance ID"
  value       = module.db.db_instance_identifier
}

output "db_instance_name" {
  description = "The database name"
  value       = module.db.db_instance_name
}

output "db_instance_username" {
  description = "The master username for the database"
  value       = module.db.db_instance_username
  sensitive   = true
}

output "db_instance_port" {
  description = "The database port"
  value       = module.db.db_instance_port
}

output "db_security_group_id" {
  description = "The security group ID of the database"
  value       = aws_security_group.database.id
}

output "kms_key_arn" {
  description = "The ARN of the KMS key used for RDS encryption"
  value       = local.kms_key_arn
}

output "kms_key_id" {
  description = "The ID of the KMS key used for RDS encryption (only if created by this module)"
  value       = var.create_kms_key ? aws_kms_key.rds[0].key_id : null
}

output "kms_key_alias" {
  description = "The alias of the KMS key used for RDS encryption"
  value       = var.create_kms_key ? aws_kms_alias.rds[0].name : null
}
