terraform {
  required_version = ">= 1.10"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0.0, < 3.4.0"
    }
  }
}
