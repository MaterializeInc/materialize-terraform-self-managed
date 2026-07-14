# Materialize on Azure Terraform Modules

This repository provides a set of reusable, **self-contained Terraform modules** to deploy Materialize on the Microsoft Azure cloud platform. You can use these modules individually or combine them to create your own custom infrastructure stack.

-> **Note**
-> We recommend pinning your module sources to specific tags to avoid unexpected breaking changes in future versions.
-> We recommend updating your module source tags when updating Materialize versions, taking care to follow any instructions in the release notes.

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

### Required Features

Your Azure project needs several APIs enabled. See the [examples/simple/README.md](./examples/simple/README.md#required-features) for the complete list of required APIs and how to enable them.

### NodeLocal DNSCache

The AWS and GCP examples run a node-local DNS cache on every node
(the [`kubernetes/modules/node-local-dns`](../kubernetes/modules/node-local-dns)
helm module on EKS, the built-in NodeLocal DNSCache addon on GKE). There is
currently no equivalent here: these modules use Azure CNI powered by Cilium,
whose eBPF dataplane resolves the kube-dns service IP before iptables runs, so
a self-deployed node-local-dns can never intercept pod DNS traffic, and the
managed Cilium does not expose Local Redirect Policies.

The path forward is AKS's native
[LocalDNS](https://learn.microsoft.com/en-us/azure/aks/localdns-custom)
feature (per-node-pool `--localdns-config`), which sidesteps the interception
problem entirely by pointing pod resolution at a node-local proxy on
169.254.10.10. It is blocked on azurerm provider support for
`localDNSProfile`
([hashicorp/terraform-provider-azurerm#31342](https://github.com/hashicorp/terraform-provider-azurerm/issues/31342));
adopting it will also need a Cilium network policy allowing pod egress to
169.254.10.0/24:53 wherever network policies are enabled, and enabling it
reimages the node pool.
