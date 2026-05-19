terraform {
  required_version = ">= 1.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.10.0, < 2.39.0"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "2.4.0"
    }
  }
}
