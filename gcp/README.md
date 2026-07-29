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
| [`modules/storage-class`](./modules/storage-class) | Kubernetes StorageClass for GCP Persistent Disks (optional)  |
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

## Multi-Zone Deployments

GKE supports multi-zone deployments for high availability. This section explains how networking, storage, and zones interact.

### Zone Configuration

By default, GKE regional clusters distribute nodes across all zones in the region. You can optionally restrict nodes to specific zones:

```hcl
module "gke" {
  source = "../../modules/gke"
  # ...
  region         = "us-central1"
  node_locations = ["us-central1-a", "us-central1-b"]  # Optional: limit to specific zones
}
```

**When to specify zones:**
- **Cost optimization**: Fewer zones = fewer nodes = lower cost
- **Machine type availability**: Some machine types aren't available in all zones
- **Data locality**: Keep workloads closer to specific data sources

### Networking (Subnets)

GCP subnets are **regional resources**, not zonal. A single subnet automatically spans all zones in its region. This means:
- No subnet changes needed for multi-zone deployments
- Nodes in any zone can use the same subnet and IP ranges
- Pod and service CIDR ranges work across all zones

### Storage (Persistent Disks)

GCP Persistent Disks (PDs) are **zonal resources**. A PD can only be attached to a node in the same zone. This has important implications:

#### The Problem with Default Volume Binding

With the default `Immediate` volume binding mode, Kubernetes creates the PD as soon as the PVC is created—before knowing where the pod will be scheduled. If the pod gets scheduled to a different zone than the PD, it cannot start.

#### The Solution: WaitForFirstConsumer

GKE's default storage class `standard-rwo` uses `volumeBindingMode: WaitForFirstConsumer`, which:
1. Delays PD creation until a pod using the PVC is scheduled
2. Creates the PD in the same zone as the scheduled node
3. Ensures pods can always access their volumes

**This is why we recommend using `standard-rwo` (or our storage-class module) for multi-zone deployments.**

#### Storage Class Options

| Storage Class | Disk Type | Binding Mode | Use Case |
|---------------|-----------|--------------|----------|
| `standard` | pd-standard (HDD) | Immediate | Legacy, not recommended for multi-zone |
| `standard-rwo` | pd-balanced | WaitForFirstConsumer | **Recommended default** |
| `premium-rwo` | pd-ssd | WaitForFirstConsumer | Higher performance workloads |

For custom storage classes, use the [`modules/storage-class`](./modules/storage-class) module.

#### Regional Persistent Disks

For zone-level fault tolerance, you can use Regional Persistent Disks which replicate data across two zones:

```hcl
module "storage_class" {
  source = "../../modules/storage-class"

  storage_class_name = "regional-pd-ssd"
  disk_type          = "pd-ssd"
  replication_type   = "regional-pd"
}
```

**Trade-offs:**
- Higher availability (survives single zone failure)
- Higher cost (~2x zonal PD pricing)
- Slightly higher latency for writes

### StatefulSets and Multi-Zone

StatefulSets work well with multi-zone deployments because:
- Each replica gets its own PVC
- `WaitForFirstConsumer` ensures each PD is created in the zone where its pod runs
- Pod-to-PD zone affinity is maintained across restarts
