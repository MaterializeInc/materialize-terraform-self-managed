output "instance_name" {
  description = "The name of the database instance"
  value       = module.database.instance_name
}

output "database_names" {
  description = "List of database names"
  value       = module.database.database_names
}

output "user_names" {
  description = "List of database user names"
  value       = module.database.user_names
}

output "private_ip" {
  description = "The private IP address of the database instance"
  value       = module.database.private_ip
}

output "databases" {
  description = "List of created databases"
  value       = module.database.databases
}

output "users" {
  description = "List of created users with credentials"
  value       = module.database.users
  sensitive   = true
}
