# Materialize on Azure Terraform Modules

This repository provides a set of reusable, **self-contained Terraform modules** to deploy Materialize on the Microsoft Azure cloud platform. You can use these modules individually or combine them to create your own custom infrastructure stack.

> **Note**
> These modules are intended for demonstration and prototyping purposes. If you're planning to use them in production, fork the repo and pin to a specific commit or tag to avoid breaking changes in future versions.

---

## Modular Architecture

Each module is designed to be used independently. You can compose them in any way that fits your use case.

See [`examples/simple/`](./examples/simple/) for a working example that ties the modules together into a complete environment.

---

## Available Modules

Azure Specific Modules:

| Module                                      | Description                                                      |
|---------------------------------------------|------------------------------------------------------------------|
| [`modules/networking`](./modules/networking) | VNet, subnets, NAT gateway, and networking resources            |
| [`modules/aks`](./modules/aks)              | AKS cluster with Cilium networking and workload identity        |
| [`modules/nodepool`](./modules/nodepool)    | Additional AKS node pools with autoscaling                      |
| [`modules/database`](./modules/database)    | PostgreSQL Flexible Server for Materialize metadata            |
| [`modules/storage`](./modules/storage)      | Azure Storage Account with workload identity federation         |
| [`modules/load_balancers`](./modules/load_balancers) | Azure Load Balancers for Materialize instance access |
| [`modules/operator`](./modules/operator)    | Materialize Kubernetes operator installation                    |

**Cloud-Agnostic Kubernetes Modules:**

For Kubernetes-specific modules (cert-manager, Materialize instance, etc.) that work across all cloud providers, see the [kubernetes/](../kubernetes/) directory.

See the [Kubernetes Modules README](../kubernetes/README.md) for details on:
- cert-manager installation
- Self-signed certificate issuer
- Materialize instance deployment

---

Depending on your needs, you can use the modules individually or combine them to create a setup that fits your needs.

---

## Getting Started

### Example Deployment

To deploy a simple end-to-end environment, see the [`examples/simple`](./examples/simple) folder.

```hcl
module "networking" {
  source = "../../modules/networking"
  prefix = "mz"
  # ... networking vars
}

module "aks" {
  source = "../../modules/aks"
  prefix = "mz"
  subnet_id = module.networking.aks_subnet_id
  # ... aks vars
}

# See full working setup in the examples/simple/main.tf file
```

### Providers

Ensure you configure the Azure, Kubernetes, and Helm providers. Here's a minimal setup:

```hcl
provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}

provider "kubernetes" {
  host                   = module.aks.cluster_endpoint
  client_certificate     = base64decode(module.aks.kube_config[0].client_certificate)
  client_key             = base64decode(module.aks.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(module.aks.kube_config[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = module.aks.cluster_endpoint
    client_certificate     = base64decode(module.aks.kube_config[0].client_certificate)
    client_key             = base64decode(module.aks.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(module.aks.kube_config[0].cluster_ca_certificate)
  }
}
```
