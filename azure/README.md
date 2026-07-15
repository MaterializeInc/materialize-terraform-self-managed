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
helm module on EKS, the built-in NodeLocal DNSCache addon on GKE). Azure is
deliberately skipped for now. Options considered:

- **The helm module (iptables interception)** cannot work here. The chart's
  default mode changes nothing on the node or in kubelet: the DaemonSet itself
  binds the kube-dns service IP on a dummy interface, and pods keep querying
  that IP as usual. That only works when service traffic actually leaves the
  pod addressed to the service IP. These modules use Azure CNI powered by
  Cilium, whose eBPF dataplane resolves the kube-dns service IP at connection
  time, so the NOTRACK rules and locally bound IP that make the chart work on
  EKS never see pod DNS traffic.
- **Cilium Local Redirect Policy** (how Materialize's cloud platform runs
  node-local-dns on its self-managed Cilium) is unavailable: AKS's managed
  Cilium does not enable LRP and does not accept custom Cilium CRDs.
- **Pointing kubelet's `--cluster-dns` at a node-local cache** (what the GKE
  addon does, managed) is not exposed by AKS's `kubelet_config`, so it would
  require a privileged DaemonSet that rewrites kubelet config on the host and
  restarts it. Rejected: unsupported by AKS, undone by every node
  image upgrade/reimage, and it inverts the failure mode -- with interception
  a crashed cache falls back to kube-dns, while a kubelet pointed only at a
  dead local cache takes down DNS for every pod on the node.
- **AKS's native
  [LocalDNS](https://learn.microsoft.com/en-us/azure/aks/localdns-custom)**
  (per-node-pool `--localdns-config`) is the right path: it points pod
  resolution at a node-local proxy on 169.254.10.10 run as a systemd unit, so
  no interception is needed and it survives pod-level failures. It is blocked
  on azurerm provider support for `localDNSProfile`
  ([hashicorp/terraform-provider-azurerm#31342](https://github.com/hashicorp/terraform-provider-azurerm/issues/31342)).
  A `local-exec` provisioner running `az aks nodepool update --localdns-config`
  would work today, but until the provider is localDNSProfile-aware, any later
  azurerm update to a node pool can silently drop the profile and reimage the
  pool, so it was not worth the fragility.

When adopting LocalDNS once the provider supports it, note that enabling it
reimages the node pool, and namespaces with network policies enabled need
egress to 169.254.10.0/24:53 allowed (Cilium default-denies unlisted
destinations, and LocalDNS moves pod resolution off the kube-dns service IP).
