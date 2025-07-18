output "database_endpoint" {
  description = "Database endpoint"
  value       = module.database.database_endpoint
}

output "database_port" {
  description = "Database port"
  value       = module.database.database_port
}

output "database_name" {
  description = "Database name"
  value       = module.database.database_name
}

output "database_username" {
  description = "Database username"
  value       = module.database.database_username
}

output "database_identifier" {
  description = "Database identifier"
  value       = module.database.database_identifier
}

output "database_security_group_id" {
  description = "Database security group ID"
  value       = module.database.database_security_group_id
}

output "database_subnet_group_name" {
  description = "Database subnet group name"
  value       = module.database.database_subnet_group_name
}
