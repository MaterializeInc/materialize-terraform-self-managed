locals {
  # Generate a password for users that do not set one.
  users = [
    for user in var.users : {
      name            = user.name
      password        = user.password
      random_password = (user.password == null || user.password == "") ? true : false
    }
  ]
}
module "postgresql" {
  source  = "terraform-google-modules/sql-db/google//modules/postgresql"
  version = "28.3.0"

  name                 = "${var.prefix}-pg"
  random_instance_name = var.random_instance_name
  database_version     = var.db_version
  project_id           = var.project_id
  region               = var.region
  tier                 = var.tier
  edition              = var.edition
  deletion_protection  = false

  ip_configuration = {
    ipv4_enabled    = false
    private_network = var.network_id
  }


  backup_configuration = {
    enabled                        = var.backup_enabled
    start_time                     = var.backup_start_time
    location                       = null
    point_in_time_recovery_enabled = var.point_in_time_recovery_enabled
    transaction_log_retention_days = null
    retained_backups               = var.backup_retained_backups
    # https://cloud.google.com/sql/docs/mysql/admin-api/rest/v1/instances#retentionunit
    retention_unit = var.backup_retention_unit
  }

  maintenance_window_day          = var.maintenance_window_day
  maintenance_window_hour         = var.maintenance_window_hour
  maintenance_window_update_track = var.maintenance_window_update_track

  enable_default_db   = false
  enable_default_user = false

  additional_databases = var.databases
  additional_users     = local.users

  user_labels = var.labels

  create_timeout = var.create_timeout
  update_timeout = var.update_timeout
  delete_timeout = var.delete_timeout

  disk_size             = var.disk_size
  disk_type             = var.disk_type
  disk_autoresize       = var.disk_autoresize
  disk_autoresize_limit = var.disk_autoresize_limit

  database_flags = var.database_flags

  insights_config = null

  database_deletion_policy = var.database_deletion_policy
  user_deletion_policy     = var.user_deletion_policy
}
