locals {
  # Generate random passwords for users that don't have one specified
  users = [
    for user in var.users : {
      name            = user.name
      password        = user.password
      random_password = (user.password == null || user.password == "") ? true : false
    }
  ]
}

# Generate random passwords for users that need them
resource "random_password" "user_passwords" {
  for_each = {
    for user in local.users : user.name => user
    if user.random_password
  }

  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# AlloyDB Cluster
resource "google_alloydb_cluster" "main" {
  cluster_id = "${var.prefix}-alloydb"
  project    = var.project_id
  location   = var.region

  cluster_type     = var.cluster_type
  database_version = var.database_version

  deletion_policy = var.deletion_protection ? "DEFAULT" : "FORCE"

  network_config {
    network = var.network_id
  }

  # Automated backup configuration
  dynamic "automated_backup_policy" {
    for_each = var.automated_backup_enabled ? [1] : []
    content {
      enabled = true

      backup_window = "3600s"

      weekly_schedule {
        start_times {
          hours   = var.automated_backup_start_hour
          minutes = 0
          seconds = 0
          nanos   = 0
        }
        days_of_week = var.automated_backup_days
      }

      quantity_based_retention {
        count = var.backup_retention_days
      }
    }
  }

  # Continuous backup (PITR) configuration
  continuous_backup_config {
    enabled              = var.continuous_backup_enabled
    recovery_window_days = var.continuous_backup_retention_days
  }

  # Maintenance window
  maintenance_update_policy {
    maintenance_windows {
      day = var.maintenance_window_day
      start_time {
        hours   = var.maintenance_window_hour
        minutes = 0
        seconds = 0
        nanos   = 0
      }
    }
  }

  labels = var.labels
}

# AlloyDB Primary Instance
resource "google_alloydb_instance" "primary" {
  cluster       = google_alloydb_cluster.main.name
  instance_id   = "${var.prefix}-alloydb-primary"
  instance_type = "PRIMARY"

  machine_config {
    cpu_count = var.cpu_count
  }

  availability_type = var.availability_type

  # Database flags (as a map)
  database_flags = var.database_flags

  # Query insights
  query_insights_config {
    query_string_length     = var.query_insights_enabled ? var.query_string_length : null
    record_application_tags = var.query_insights_enabled ? var.record_application_tags : null
    record_client_address   = var.query_insights_enabled ? var.record_client_address : null
    query_plans_per_minute  = var.query_insights_enabled ? var.query_plans_per_minute : null
  }

  labels = var.labels
}

# AlloyDB Users
resource "google_alloydb_user" "users" {
  for_each = { for user in local.users : user.name => user }

  cluster        = google_alloydb_cluster.main.name
  user_id        = each.value.name
  user_type      = "ALLOYDB_BUILT_IN"
  database_roles = ["alloydbsuperuser"]

  password = each.value.random_password ? random_password.user_passwords[each.key].result : each.value.password

  depends_on = [google_alloydb_instance.primary]
}
