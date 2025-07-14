provider "google" {
  project = var.project_id
  region  = var.region
}

# Database test example - receives network info from test
module "database" {
  source = "../../modules/database"

  database_name = var.database_name
  database_user = var.user_name

  project_id = var.project_id
  network_id = var.network_id
  region     = var.region
  prefix     = var.prefix
  tier       = var.database_tier
  db_version = var.db_version
  password   = var.database_password
}

