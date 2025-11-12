# Materialize on GCP Terraform Modules

This repository provides a set of reusable, **self-contained Terraform modules** to deploy Materialize on the Google Cloud Platform. You can use these modules individually or combine them to create your own custom infrastructure stack.

> **Note**
> These modules are intended for demonstration and prototyping purposes. If you're planning to use them in production, fork the repo and pin to a specific commit or tag to avoid breaking changes in future versions.

---

## Modular Architecture

Each module is designed to be used independently. You can compose them in any way that fits your use case.

See [`examples/simple/`](./examples/simple/) for a working example that ties the modules together into a complete environment.

---

## Available Modules

GCP Specific Modules:

| Module                                          | Description                                                    |
|-------------------------------------------------|----------------------------------------------------------------|
| [`modules/networking`](./modules/networking)    | VPC, subnets, Cloud NAT, and networking resources              |
| [`modules/gke`](./modules/gke)                  | GKE cluster with workload identity                             |
| [`modules/nodepool`](./modules/nodepool)        | Additional GKE node pools with autoscaling                     |
| [`modules/database`](./modules/database)        | Cloud SQL PostgreSQL for Materialize metadata                 |
| [`modules/storage`](./modules/storage)          | Cloud Storage bucket with HMAC keys for S3-compatible access   |
| [`modules/load_balancers`](./modules/load_balancers) | GCP Load Balancers for Materialize instance access      |
| [`modules/operator`](./modules/operator)        | Materialize Kubernetes operator installation                   |

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
  project_id = var.project_id
  prefix = "mz"
  # ... networking vars
}

module "gke" {
  source = "../../modules/gke"
  project_id = var.project_id
  prefix = "mz"
  network_name = module.networking.network_name
  # ... gke vars
}

# See full working setup in the examples/simple/main.tf file
```

### Providers

Ensure you configure the GCP, Kubernetes, and Helm providers. Here's a minimal setup:

```hcl
provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${module.gke.cluster_endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = "https://${module.gke.cluster_endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)
  }
}
```

### Required APIs

Your GCP project needs several APIs enabled. See the [examples/simple/README.md](./examples/simple/README.md#required-apis) for the complete list of required APIs and how to enable them.
