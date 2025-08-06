module "postgresql" {
  source  = "terraform-google-modules/sql-db/google//modules/postgresql"
  version = "26.1.1"

  name                = "${var.prefix}-pg"
  database_version    = var.db_version
  project_id          = var.project_id
  region              = var.region
  tier                = var.tier
  deletion_protection = false

  # Network configuration
  ip_configuration = {
    ipv4_enabled    = false
    private_network = var.network_id
  }

  # Backup configuration
  backup_configuration = {
    enabled                        = var.backup_enabled
    start_time                     = var.backup_start_time
    location                       = null
    point_in_time_recovery_enabled = var.point_in_time_recovery_enabled
    transaction_log_retention_days = null
    retained_backups               = var.backup_retained_backups
    retention_unit                 = var.backup_retention_unit
  }

  # Maintenance configuration
  maintenance_window_day          = var.maintenance_window_day
  maintenance_window_hour         = var.maintenance_window_hour
  maintenance_window_update_track = var.maintenance_window_update_track

  # Disable default database and user creation
  enable_default_db   = false
  enable_default_user = false

  # Additional databases and users (mandatory)
  additional_databases = var.databases
  additional_users     = var.users

  # Labels
  user_labels = var.labels

  # Module specific settings
  create_timeout = var.create_timeout
  update_timeout = var.update_timeout
  delete_timeout = var.delete_timeout

  # Disk settings
  disk_size             = var.disk_size
  disk_type             = var.disk_type
  disk_autoresize       = var.disk_autoresize
  disk_autoresize_limit = var.disk_autoresize_limit

  # Database flags
  database_flags = var.database_flags

  # Insights configuration
  insights_config = null

  # Deletion policies
  database_deletion_policy = var.database_deletion_policy
  user_deletion_policy     = var.user_deletion_policy
}
