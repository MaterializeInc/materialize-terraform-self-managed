output "instance_name" {
  description = "The name of the database instance"
  value       = google_sql_database_instance.materialize.name
}

output "database_name" {
  description = "The name of the database"
  value       = google_sql_database.materialize.name
}

output "user_name" {
  description = "The name of the database user"
  value       = google_sql_user.materialize.name
}

output "private_ip" {
  description = "The private IP address of the database instance"
  value       = google_sql_database_instance.materialize.private_ip_address
}

output "connection_url" {
  description = "The connection URL for the database"
  value = format(
    "postgres://%s:%s@%s/%s?sslmode=verify-ca",
    google_sql_user.materialize.name,
    var.password,
    google_sql_database_instance.materialize.private_ip_address,
    google_sql_database.materialize.name
  )
  sensitive = true
}
