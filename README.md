# Materialize Self-Managed Terraform Modules

---

## About Materialize

Materialize is a real-time data integration platform that creates and continually updates consistent views of transactional data from across your organization. Its SQL interface democratizes the ability to serve and access live data. Materialize can be deployed anywhere your infrastructure runs.

Use Materialize to do things like deliver fresh context for AI/RAG pipelines, power operational dashboards, and create more dynamic customer experiences without building time-consuming custom data pipelines.

The three most common patterns for adopting Materialize are the following:

Query Offload (CQRS) - Scale complex read queries more efficiently than a read replica, and without the headaches of cache invalidation.
Integration Hub (ODS) - Extract, load, and incrementally transform data from multiple sources. Create live views of your data that can be queried directly or pushed downstream.
Operational Data Mesh (ODM) - Use SQL to create and deliver real-time, strongly consistent data products to streamline coordination across services and domains.

---

## Overview

This repository provides production-ready Terraform modules for deploying Materialize in self-managed environments across AWS, Azure, and Google Cloud Platform. The modules are designed to be composable, allowing you to use them individually or combine them to build complete infrastructure stacks.

### Architecture

A typical Materialize deployment consists of:

**Cloud Infrastructure Layer:**
- **Networking**: VPC/VNet with private and public subnets, NAT gateways, and network security
- **Kubernetes Cluster**: Managed Kubernetes service (EKS, AKS, or GKE) with autoscaling node groups
- **Metadata Store**: Managed PostgreSQL database for Materialize system catalog and metadata
- **Object Storage**: S3/Blob Storage/GCS for Materialize's persistent data layer
- **Load Balancing**: Cloud-native load balancers for exposing Materialize services

**Kubernetes Application Layer:**
- **Materialize Operator**: Kubernetes operator that manages Materialize instances
- **Cert-Manager**: Certificate management for TLS
- **Materialize Instance**: The actual Materialize deployment with configurable resources

### Repository Structure

```
├── aws/                    # AWS-specific infrastructure modules
│   ├── modules/           # Reusable AWS modules (VPC, EKS, RDS, S3, etc.)
│   └── examples/simple/   # Complete AWS deployment example
├── azure/                  # Azure-specific infrastructure modules
│   ├── modules/           # Reusable Azure modules (VNet, AKS, PostgreSQL, Storage, etc.)
│   └── examples/simple/   # Complete Azure deployment example
├── gcp/                    # GCP-specific infrastructure modules
│   ├── modules/           # Reusable GCP modules (VPC, GKE, CloudSQL, GCS, etc.)
│   └── examples/simple/   # Complete GCP deployment example
├── kubernetes/             # Cloud-agnostic Kubernetes modules
│   └── modules/           # Cert-manager, Materialize instance, etc.
└── test/                   # Terratest integration tests
```

---

## Cloud Provider Support

### AWS

Complete support for deploying Materialize on Amazon Web Services with EKS, RDS PostgreSQL, and S3.

**Key Features:**
- EKS cluster with **Karpenter** for advanced node autoscaling and efficient resource management
- RDS PostgreSQL for metadata storage
- S3 with IRSA for secure, passwordless access
- Network Load Balancer for service exposure
- Multi-AZ deployment support

**Autoscaling:** Uses [Karpenter](https://karpenter.sh/docs/), to provision right-sized nodes based on pending pod requirements, offering better bin-packing and faster scale-up compared to cluster autoscaler.

**Get Started:** See [aws/examples/simple/README.md](./aws/examples/simple/README.md) for detailed deployment instructions and architecture.

### Azure

Complete support for deploying Materialize on Microsoft Azure with AKS, Azure Database for PostgreSQL, and Azure Storage.

**Key Features:**
- AKS cluster with Cilium networking
- PostgreSQL Flexible Server for metadata storage
- Azure Storage with Workload Identity federation for secure access
- Azure Load Balancer for service exposure
- Multi-zone deployment support

**Autoscaling:** Uses Azure's native cluster autoscaler that integrates directly with Azure Virtual Machine Scale Sets for automated node scaling. In future we are planning to enhance this by making use of [karpenter-provider-azure](https://github.com/Azure/karpenter-provider-azure)

**Get Started:** See [azure/examples/simple/README.md](./azure/examples/simple/README.md) for detailed deployment instructions and architecture.

### GCP

Complete support for deploying Materialize on Google Cloud Platform with GKE, Cloud SQL, and Cloud Storage.

**Key Features:**
- GKE cluster with Workload Identity
- Cloud SQL PostgreSQL for metadata storage
- Cloud Storage with HMAC keys for S3-compatible access
- GCP Load Balancer for service exposure
- Regional deployment support

**Autoscaling:** Uses GKE's native cluster autoscaler that integrates with Google Compute Engine managed instance groups for automated node scaling.

**Get Started:** See [gcp/examples/simple/README.md](./gcp/examples/simple/README.md) for detailed deployment instructions and architecture.

---

## Unsupported Features & Known Limitations

### GCP Storage Authentication

**Limitation:** Materialize currently only supports HMAC key authentication for GCS access (S3-compatible API).

**Current State:** The modules configure both HMAC keys and Workload Identity, but Materialize uses HMAC keys for actual storage access.

**Future:** Native GCS access via Workload Identity Federation or Kubernetes service account impersonation will be supported in a future release, eliminating the need for static credentials.

---

## Getting Started

### Prerequisites

- Terraform >= 1.0
- Cloud provider credentials configured
- kubectl (for managing Kubernetes resources)
- Appropriate cloud provider CLI tools (aws-cli, az, or gcloud)

### Quick Start

1. **Choose your cloud provider** and navigate to the example directory

    `cd <cloud-provider>/examples/simple`
2. **Review the example README** for cloud-specific prerequisites and configuration
3. **Instantiate modules in your terraform stack**.

    The examples are just that: examples. They aren't meant for you to run directly, but to serve as something to base your own module instantiations on.
4. **Set required variables** in a `terraform.tfvars` file
5. **Deploy the infrastructure:**

```bash
terraform init
terraform plan
terraform apply
```

4. **Connect to your Materialize instance** using the connection details from the Terraform outputs

### Module Usage

All modules can be used independently. For example, if you already have a Kubernetes cluster, you can use just the Materialize-specific modules:

```hcl
module "materialize_instance" {
  source               = "github.com/MaterializeInc/materialize-terraform-self-managed//kubernetes/modules/materialize-instance?ref=<tag>"
  instance_name        = "production"
  instance_namespace   = "materialize"
  metadata_backend_url = "postgres://user:pass@host/db"
  persist_backend_url  = "s3://bucket-name/prefix"
  # ... additional configuration
}
```

Set the `ref=` portion to point at the latest tagged version of this repository.

## Upgrading

Most of the time, you just need to bump the `ref=<tag>` in all modules. We recommend that you bump all modules to the same version in the same `terraform apply`. We frequently make changes that assume related changes in dependent modules.

Upgrades of the materialize version are included in our tagged releases. We do not recommend overriding the Materialize version, orchestratord version, or helm chart version. Updating the module tags will automatically pick up the latest versions of these components.

We follow semantic versioning with our tags. If a particular version requires additional actions or contains breaking changes, we will list them below.

### Upgrade Notes

#### v5.0.0

The GCP examples default to new machine types for higher performance and due to capacity constraints with the previous types:

- Generic node pool: `e2-standard-8` → `c4-standard-8`
- Materialize node pool: `n2-highmem-8` → `c4a-highmem-8-lssd` (Arm-based; local SSDs are bundled, so `local_ssd_count` is now 2)
- Cloud SQL: `db-custom-2-4096` → `db-custom-N4-2-4096` with `HYPERDISK_BALANCED` disk (N4 does not support `PD_SSD`)

The nodepool module gained a `disk_type` variable. C4 and C4A only support Hyperdisk boot disks, and an existing node pool keeps its old disk type when the machine type changes, so set `disk_type = "hyperdisk-balanced"` (the examples now do) when moving to these machine types.

**Impact on existing deployments:**

These changes are for the examples. You are not required to change your existing infrastructure at this time, but future testing and performance profiling will be done using the newer machine and disk types. As such, we recommend updating your configuration at your convenience.

- **Node pools**: Do not change the machine type on an existing materialize node pool. Instead, migrate blue-green:
  1. Bump `ref=<tag>` on all modules, keeping your existing machine types, `disk_type`, and database tier unchanged. The tag bump alone doesn't modify existing node pools (`disk_type` defaults to `null`), and it makes the new `disk_type` variable available for the next step. Don't set `disk_type` on the old pool — Hyperdisk is not supported on the older machine series.
  2. Add a new nodepool module instance with the new machine type and `disk_type` (use a new `prefix` so the pool gets a distinct name), keeping the old pool unchanged. For a swap-enabled pool, also set a distinct `disk_setup_name` (e.g. `disk-setup-v2`) — it names the disk-setup namespace and daemonset, which otherwise collide with the old pool's. Also update the `local_ssd_count` for the new instance type (`c4a-highmem-8-lssd` has 2, for example).
  3. `terraform apply` to create the new node pool.
  4. Add a decommission taint to the old pool's `node_taints`, for example:

     ```hcl
     node_taints = [
       # ... existing taints ...
       {
         key    = "materialize.cloud/decommissioned"
         value  = "true"
         effect = "NO_SCHEDULE"
       }
     ]
     ```

     Taints update in place (no pool replacement) on the provider versions these modules require. Running pods are not evicted, but no new pods schedule to the old pool, and the cluster autoscaler will not scale it up for pending pods, since they don't tolerate the taint. Use a taint key the Materialize pods don't tolerate (not `materialize.cloud/workload` or `kubernetes.io/arch`).
  5. `terraform apply` to apply the decommision taint to the old pool.
  6. Prepare a rollout of your Materialize instances by setting the `force_rollout` field to a new UUID. If you have reverted back into the `v1alpha1` version of the Materialize CRD, also set `request_rollout` to the same UUID.
  7. `terraform apply` to perform the rollout.
  8. Verify the new environmentd and clusterd pods are only scheduled onto the new pool.
  9. Remove the old nodepool module instance from your configuration.
  10. `terraform apply` to delete the old pool.
- **Cloud SQL**: Do **not** adopt the new tier and disk type on an existing instance. `disk_type` changes force instance replacement, which destroys the Materialize metadata database, and Cloud SQL reserves deleted instance names for up to a week, so the recreate also fails with a 409. Keep existing instances pinned to their current tier (`db-custom-2-4096`) and disk type (`PD_SSD`); the N4 default is for new deployments only.

C4, C4A, and N4 are not available in every region. Verify availability in your region before upgrading, or keep the previous types.

#### v4.0.0

Default to v1 of the Materialize CRD.

Changes will be rolled out immediately, without needing to update the `request_rollout` variable.

#### v3.0.0

Kubernetes version 1.34.

#### v2.0.0

Kubernetes version 1.33.

---

## Development & Contributing

We welcome contributions! Please see [CONTRIBUTING.md](./CONTRIBUTING.md) for development setup, testing instructions, and contribution guidelines.

### Documentation Generation

This project uses [terraform-docs](https://terraform-docs.io/) to auto-generate module documentation. To regenerate documentation after making changes:

```bash
.github/scripts/generate-docs.sh
```

### Testing

The repository includes comprehensive integration tests using Terratest. See [test/README.md](./test/README.md) for testing architecture and instructions.

---

## License

See [LICENSE](./LICENSE) file for details.

---

## Support

- **Documentation**: [materialize.com/docs/self-managed](https://materialize.com/docs/self-managed/)
- **Community**: [Materialize Community Slack](https://materialize.com/s/chat)
- **Issues**: [GitHub Issues](https://github.com/MaterializeInc/materialize-terraform-self-managed/issues)
