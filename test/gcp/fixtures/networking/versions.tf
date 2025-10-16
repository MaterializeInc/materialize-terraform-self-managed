terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.31, < 7"
    }
  }

  # S3 backend configuration (configured dynamically via -backend-config flags)
  backend "s3" {}
}
