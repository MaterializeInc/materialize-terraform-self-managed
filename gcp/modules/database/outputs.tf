output "instance_name" {
  description = "The name of the database instance"
  value       = module.postgresql.instance_name
}

output "database_names" {
  description = "List of database names"
  value       = [for db in var.databases : db.name]
}

output "user_names" {
  description = "List of database user names"
  value       = [for user in var.users : user.name]
}

output "private_ip" {
  description = "The private IP address of the database instance"
  value       = module.postgresql.private_ip_address
}

output "users" {
  description = "List of created users with their credentials"
  value       = module.postgresql.additional_users
  sensitive   = true
}

output "databases" {
  description = "List of created databases"
  value       = var.databases
}
