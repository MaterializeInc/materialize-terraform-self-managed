output "cluster_id" {
  description = "The ID of the AlloyDB cluster"
  value       = google_alloydb_cluster.main.cluster_id
}

output "cluster_name" {
  description = "The full resource name of the AlloyDB cluster"
  value       = google_alloydb_cluster.main.name
}

output "instance_name" {
  description = "The name of the primary instance (matches database module interface)"
  value       = google_alloydb_instance.primary.instance_id
}

output "instance_id" {
  description = "The full resource name of the primary instance"
  value       = google_alloydb_instance.primary.name
}

output "private_ip" {
  description = "The private IP address of the primary instance (matches database module interface)"
  value       = google_alloydb_instance.primary.ip_address
}

output "database_names" {
  description = "List of database names (note: AlloyDB creates 'postgres' by default)"
  value       = length(var.databases) > 0 ? [for db in var.databases : db.name] : ["postgres"]
}

output "user_names" {
  description = "List of database user names"
  value       = [for user in var.users : user.name]
}

output "users" {
  description = "List of created users with their credentials (matches database module interface)"
  value = [
    for user in local.users : {
      name     = user.name
      password = user.random_password ? random_password.user_passwords[user.name].result : user.password
    }
  ]
  sensitive = true
}

output "databases" {
  description = "List of databases"
  value       = length(var.databases) > 0 ? var.databases : [{ name = "postgres", charset = "UTF8", collation = "en_US.UTF8" }]
}

output "connection_uri" {
  description = "PostgreSQL connection URI format"
  value       = "postgresql://${google_alloydb_instance.primary.ip_address}:5432/postgres"
}
