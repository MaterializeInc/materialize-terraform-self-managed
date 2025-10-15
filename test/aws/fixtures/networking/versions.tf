terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  # S3 backend configuration (configured dynamically via -backend-config flags)
  backend "s3" {}
}
