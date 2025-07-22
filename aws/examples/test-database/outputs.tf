output "database_endpoint" {
  description = "Database endpoint"
  value       = module.database.db_instance_endpoint
}

output "database_port" {
  description = "Database port"
  value       = module.database.db_instance_port
}

output "database_name" {
  description = "Database name"
  value       = module.database.db_instance_name
}

output "database_username" {
  description = "Database username"
  value       = module.database.db_instance_username
  sensitive   = true
}

output "database_identifier" {
  description = "Database identifier"
  value       = module.database.db_instance_id
}

# output "database_security_group_id" {
#   description = "Database security group ID"
#   value       = module.database.database_security_group_id
# }
