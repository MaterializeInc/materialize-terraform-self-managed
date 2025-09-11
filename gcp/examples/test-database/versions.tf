terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.31, < 7"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}
