# Materialize on GCP Terraform Modules

This repository provides a set of reusable, **self-contained Terraform modules** to deploy Materialize on the Google Cloud Platform. You can use these modules individually or combine them to create your own custom infrastructure stack.

-> **Note**
-> We recommend pinning your module sources to specific tags to avoid unexpected breaking changes in future versions.
-> We recommend updating your module source tags when updating Materialize versions, taking care to follow any instructions in the release notes.

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

---

## Multi-Zone Clusters and Persistent Disk Topology

GKE regional clusters automatically distribute nodes across multiple zones for high availability. This section explains how zone selection interacts with GCP Persistent Disks.

### How It Works

**Networking (Regional):**
- GCP subnets are regional resources that span all zones in a region
- The networking module creates regional subnets, so no changes are needed for multi-zone clusters
- Pods in any zone can use the same subnet

**Storage (Zonal):**
- GCP Persistent Disks are zonal resources tied to a specific zone
- Pods using a PersistentVolumeClaim (PVC) must schedule in the same zone as their Persistent Disk
- GKE's default `standard-rwo` StorageClass uses `volumeBindingMode: WaitForFirstConsumer`, which delays PD creation until a pod is scheduled, ensuring the PD is created in the pod's zone

### Zone Selection

The GKE module's `node_locations` parameter controls which zones host cluster nodes:

- **Default (null)**: Uses first 3 available zones in the region for high availability
- **Explicit list**: Restricts nodes to specified zones

```hcl
module "gke" {
  source = "../../modules/gke"
  # ...

  # Default: first 3 zones in region (HA)
  # For single-zone: node_locations = ["us-east1-b"]
  # For custom zones: node_locations = ["us-east1-b", "us-east1-d"]
}
```

**When to customize zones:**
- **Single zone**: Lower cost, simpler for dev/test
- **Multiple zones**: Production HA, requires capacity in each zone
- **Specific zones**: Match machine type availability (e.g., C4A Arm instances)

### Persistent Disk Considerations

GCP Persistent Disks are zonal. The `standard-rwo` StorageClass uses `WaitForFirstConsumer` binding, which:
1. Delays PD creation until pod scheduling
2. Creates PD in same zone as scheduled pod
3. Binds pod to that zone for future restarts

For HA with stateful workloads, use multiple zones and let the scheduler place pods where capacity exists.
