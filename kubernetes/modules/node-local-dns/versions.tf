terraform {
  required_version = ">= 1.10"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.5.0, < 3.4.0"
    }
  }
}
