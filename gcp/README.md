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
| [`modules/monitoring`](./modules/monitoring)     | Observability stack (Loki, Thanos, Grafana, Alloy) with GCS buckets and Workload Identity |

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

Your GCP project needs several APIs enabled. Run
[`scripts/enable-gcp-apis.sh`](../scripts/enable-gcp-apis.sh) against your
project; the script doubles as the annotated list of what each API is for.

```bash
scripts/enable-gcp-apis.sh YOUR_PROJECT_ID
```

### Required Permissions

Enabling the APIs is not sufficient on its own: the identity that runs `terraform apply` also needs permission to create the resources. The following predefined roles, granted at project scope, cover a default deployment.

| Role                                  | Required for                                                                 | Modules                     |
|---------------------------------------|------------------------------------------------------------------------------|-----------------------------|
| `roles/compute.networkAdmin`          | VPC, subnets, Cloud NAT router, global address, private service networking peering | `networking`           |
| `roles/compute.securityAdmin`         | Firewall rules                                                                | `gke`, `load_balancers`     |
| `roles/container.admin`               | GKE cluster and node pools, and in-cluster access for the Kubernetes and Helm providers | `gke`, `nodepool`, `operator` |
| `roles/cloudsql.admin`                | Cloud SQL PostgreSQL instance                                                 | `database`                  |
| `roles/storage.admin`                 | Cloud Storage buckets and objects                                             | `storage`, `monitoring`     |
| `roles/storage.hmacKeyAdmin`          | HMAC key for S3-compatible bucket access                                      | `storage`                   |
| `roles/iam.serviceAccountAdmin`       | Creating service accounts and their Workload Identity bindings                | `gke`, `monitoring`         |
| `roles/iam.serviceAccountUser`        | Attaching the node service account to the node pool (`actAs`)                 | `gke`, `nodepool`           |
| `roles/serviceusage.serviceUsageAdmin`| Enabling the required APIs                                                    | —                           |

Two optional features need additional roles:

| Role                                    | Required when                                                                        |
|-----------------------------------------|--------------------------------------------------------------------------------------|
| `roles/pubsub.admin`                    | `enable_upgrade_notifications = true` (**the default**) — creates the notification topic and subscription |
| `roles/resourcemanager.projectIamAdmin` | `enable_upgrade_notifications = true` (**the default**), or `enable_google_cloud_metrics = true` — both add a project-level IAM binding |

To grant the full default set:

```bash
PROJECT_ID=your-project-id
MEMBER=user:you@example.com   # or serviceAccount:deployer@your-project-id.iam.gserviceaccount.com

for ROLE in \
  roles/compute.networkAdmin \
  roles/compute.securityAdmin \
  roles/container.admin \
  roles/cloudsql.admin \
  roles/storage.admin \
  roles/storage.hmacKeyAdmin \
  roles/iam.serviceAccountAdmin \
  roles/iam.serviceAccountUser \
  roles/serviceusage.serviceUsageAdmin \
  roles/pubsub.admin \
  roles/resourcemanager.projectIamAdmin
do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="$MEMBER" --role="$ROLE" --condition=None
done
```

#### Deploying without project-level IAM permissions

`roles/resourcemanager.projectIamAdmin` allows its holder to grant any role to any principal, including themselves. Many organizations will not approve it for a deployment identity.

It is only required because two optional features add project-level IAM bindings. Disabling both removes the requirement entirely:

```hcl
module "gke" {
  # ...
  enable_upgrade_notifications = false  # default is true
}

module "monitoring" {
  # ...
  enable_google_cloud_metrics = false  # already the default
}
```

With those disabled you can drop both `roles/resourcemanager.projectIamAdmin` and `roles/pubsub.admin` from the list above. The trade-off is that the operator module's `enable_node_upgrade_rollout_trigger` depends on upgrade notifications and will be unavailable.

-> **Note**
-> These roles are only needed while Terraform is running, and only on the project being deployed into.
-> For shared or production environments, prefer granting them to a dedicated deployer service account and having engineers impersonate it, rather than granting them to individual users.

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
