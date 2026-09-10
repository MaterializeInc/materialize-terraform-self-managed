terraform {
  required_version = ">= 1.10"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.10.0, < 3.3.0"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "2.4.1"
    }
  }
}
