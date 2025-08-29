output "server_name" {
  description = "The name of the PostgreSQL server"
  value       = module.database.server_name
}

output "server_fqdn" {
  description = "The FQDN of the PostgreSQL server"
  value       = module.database.server_fqdn
}

output "administrator_login" {
  description = "The administrator login for the PostgreSQL server"
  value       = module.database.administrator_login
}

output "administrator_password" {
  description = "The administrator password for the PostgreSQL server"
  value       = module.database.administrator_password
  sensitive   = true
}

output "databases" {
  description = "The databases"
  value       = module.database.databases
}

output "database_names" {
  description = "The names of the databases"
  value       = module.database.database_names
}
