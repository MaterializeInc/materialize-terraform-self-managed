output "instance_name" {
  description = "The name of the database instance"
  value       = module.database.instance_name
}

output "database_name" {
  description = "The name of the database"
  value       = module.database.database_name
}

output "user_name" {
  description = "The name of the database user"
  value       = module.database.user_name
}

output "private_ip" {
  description = "The private IP address of the database instance"
  value       = module.database.private_ip
}

output "connection_url" {
  description = "The connection URL for the database"
  value       = module.database.connection_url
  sensitive   = true
}
