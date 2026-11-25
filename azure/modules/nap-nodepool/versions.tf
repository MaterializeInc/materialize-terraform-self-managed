terraform {
  required_version = ">= 1.10"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.10.0, < 3.6.0"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "3.0.1"
    }
  }
}
