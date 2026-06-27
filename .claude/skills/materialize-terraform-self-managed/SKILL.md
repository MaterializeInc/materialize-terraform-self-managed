---
name: materialize-terraform-self-managed
description: >-
  Terraform modules for deploying self-managed Materialize on AWS (EKS),
  Azure (AKS), and GCP (GKE). Covers networking, Kubernetes clusters,
  managed PostgreSQL, object storage, the Materialize operator, and
  Materialize instance configuration. Use this skill whenever the user
  asks about deploying self-managed Materialize with Terraform, setting
  up Materialize infrastructure on any cloud, configuring EKS/AKS/GKE
  for Materialize, troubleshooting a self-managed deployment, upgrading
  Materialize instances, customizing Terraform variables for Materialize,
  or working with the materialize-terraform-self-managed repository.
  Also trigger when the user mentions Karpenter node pools for
  Materialize, persist or metadata backend URLs, the Materialize
  operator Helm chart, CRD versions (v1alpha1 vs v1), rollout
  strategies, or NVMe swap configuration for Materialize nodes.
---

# Materialize Terraform Self-Managed Modules

Production-ready Terraform modules for deploying Materialize on AWS, Azure, and GCP. Each cloud provider has its own set of modules plus shared Kubernetes modules for the operator and Materialize instance.

## Repository Layout

```
aws/
  modules/         # AWS-specific infra modules
  examples/
    simple/        # Minimal production-like deployment
    enterprise/    # Adds Ory (Kratos + Hydra) for auth
azure/
  modules/         # Azure-specific infra modules
  examples/
    simple/
    enterprise/
gcp/
  modules/         # GCP-specific infra modules
  examples/
    simple/
    enterprise/
kubernetes/
  modules/         # Cloud-agnostic K8s modules (operator, instance, cert-manager)
test/              # Rust-based integration test harness
scripts/           # Migration and utility scripts
```

## How to Use This Skill

1. **User wants to deploy Materialize on a specific cloud**: Start with the relevant `<cloud>/examples/simple/` directory. Read `main.tf` and `variables.tf` there for the full working configuration.
2. **User asks about a specific module**: Read `<cloud>/modules/<name>/variables.tf` and `main.tf` for that module.
3. **User wants to customize the instance**: Read `kubernetes/modules/materialize-instance/variables.tf` for all instance-level options.
4. **User asks about upgrades or rollouts**: See the Upgrades section below and `kubernetes/modules/materialize-instance/variables.tf` for rollout config.
5. **User wants enterprise/auth setup**: Read `<cloud>/examples/enterprise/`.

## Architecture Layers

Every deployment creates two layers:

**Cloud infrastructure** (cloud-specific modules):
- Networking: VPC/VNet, subnets, NAT, security groups
- Kubernetes: EKS/AKS/GKE cluster with autoscaling
- Database: Managed PostgreSQL for Materialize metadata
- Storage: Object storage (S3/Blob/GCS) for persist layer

**Kubernetes application** (shared modules under `kubernetes/modules/`):
- cert-manager for TLS certificates
- Materialize Operator (Helm chart)
- Materialize Instance (custom resource)

## Cloud Provider Modules

### AWS (`aws/modules/`)

| Module | Purpose |
|--------|---------|
| `networking` | VPC, subnets, NAT gateways, security groups |
| `eks` | EKS cluster with OIDC provider |
| `eks-node-group` | Managed node groups for base workloads |
| `karpenter` | Karpenter autoscaler controller |
| `karpenter-ec2nodeclass` | EC2NodeClass for Karpenter provisioning |
| `karpenter-nodepool` | NodePool for Karpenter scheduling |
| `database` | RDS PostgreSQL for metadata |
| `storage` | S3 bucket with IRSA |
| `aws-lbc` | AWS Load Balancer Controller |
| `nlb` | Network Load Balancer |
| `operator` | Materialize operator (Helm) |
| `ebs-csi-driver` | EBS CSI driver |
| `vpc-cni` | VPC CNI with network policy support |

**Key AWS patterns:**
- Node autoscaling via Karpenter (not cluster autoscaler)
- Two Karpenter node classes: generic (t4g.xlarge) and Materialize (r7gd.2xlarge with NVMe swap)
- Storage auth via IRSA (IAM Roles for Service Accounts)
- NLB for external access on ports 6875 (SQL), 6876 (HTTP), 8080 (console)

### Azure (`azure/modules/`)

| Module | Purpose |
|--------|---------|
| `networking` | VNet, subnets, NAT gateway |
| `aks` | AKS cluster with Cilium networking |
| `nodepool` | Additional AKS node pools |
| `database` | PostgreSQL Flexible Server |
| `storage` | Storage Account with workload identity |
| `load_balancers` | Azure Load Balancers |
| `operator` | Materialize operator (Helm) |

**Key Azure patterns:**
- Cilium for networking and network policies
- Workload Identity Federation for storage auth (passwordless OIDC)
- Standard_E4pds_v6 instances for Materialize nodes with swap
- Private DNS zone for PostgreSQL resolution
- Requires registering `EnableAPIServerVnetIntegrationPreview` feature

### GCP (`gcp/modules/`)

| Module | Purpose |
|--------|---------|
| `networking` | VPC, subnets, Cloud NAT |
| `gke` | GKE cluster with Workload Identity |
| `nodepool` | Additional GKE node pools |
| `database` | Cloud SQL PostgreSQL |
| `storage` | Cloud Storage bucket with HMAC keys |
| `load_balancers` | GCP Load Balancers |
| `operator` | Materialize operator (Helm) |

**Key GCP patterns:**
- HMAC keys for S3-compatible GCS access (these modules use the S3-compatible API)
- VPC peering for Cloud SQL private access
- n2-highmem-8 instances for Materialize nodes with local SSD and swap
- Secondary IP ranges for pods and services (VPC-native)
- Requires enabling multiple GCP APIs (container, compute, sqladmin, servicenetworking, etc.)

## Kubernetes Modules (`kubernetes/modules/`)

| Module | Purpose |
|--------|---------|
| `cert-manager` | Installs cert-manager Helm chart |
| `self-signed-cluster-issuer` | Creates self-signed ClusterIssuer |
| `materialize-instance` | Deploys Materialize CR |
| `coredns` | CoreDNS configuration |
| `grafana` | Grafana monitoring |
| `prometheus` | Prometheus monitoring stack |
| `hpa` | Horizontal Pod Autoscaling |
| `ory-*` | Ory stack (Kratos, Hydra, etc.) for enterprise auth |

### Materialize Instance Module

This is the most important Kubernetes module. Key variables in `kubernetes/modules/materialize-instance/variables.tf`:

| Variable | Default | Notes |
|----------|---------|-------|
| `crd_version` | `v1alpha1` | Use `v1` for v26.30+. See CRD section below. |
| `instance_name` | (required) | Name of the Materialize CR |
| `instance_namespace` | (required) | Namespace for the instance |
| `metadata_backend_url` | (required) | PostgreSQL connection string |
| `persist_backend_url` | (required) | Object storage URL |
| `license_key` | null | Community or enterprise key |
| `environmentd_version` | `v26.29.0` | Materialize version |
| `rollout_strategy` | `WaitUntilReady` | See Rollout Strategies below |
| `authenticator_kind` | `None` | Options: None, Password, Sasl, Oidc |
| `cpu_request` | `1` | CPU request for environmentd |
| `memory_request` | `4095Mi` | Memory request for environmentd |
| `memory_limit` | `4Gi` | Memory limit for environmentd |
| `system_parameters` | `{}` | Map of system config parameters |
| `issuer_ref` | null | cert-manager issuer for TLS |
| `internal_issuer_ref` | null | Override for internal mTLS certs |

## Backend URL Formats

The Materialize instance needs two backend URLs:

**Metadata backend (PostgreSQL):**
```
postgres://user:password@host:5432/database?sslmode=require&options=-c%20statement_timeout%3D15min
```
The `statement_timeout=15min` parameter is required for metadata operations.

**Persist backend (object storage):**

AWS S3:
```
s3://bucket-name/system:serviceaccount:namespace:name
```

Azure Blob:
```
https://storageaccount.blob.core.windows.net/container
```

GCP Cloud Storage (via HMAC/S3-compatible API):
```
s3://hmac-access-id:hmac-secret@bucket-name/materialize?endpoint=https%3A%2F%2Fstorage.googleapis.com&region=us-central1
```

## CRD Versions: v1alpha1 vs v1

**v1alpha1** (default, pre-v26.30): Two-step rollout. Change spec, then set `request_rollout` to a new UUID to trigger the rollout. Gives explicit control over timing.

**v1** (recommended for v26.30+): Spec changes automatically trigger rollouts. The operator computes a hash and handles rollout. The `request_rollout` field is removed. Use `force_rollout` with a new UUID for manual triggers.

Set via `crd_version` variable in the example or the materialize-instance module.

## Rollout Strategies

| Strategy | Behavior | Resource impact |
|----------|----------|-----------------|
| `WaitUntilReady` | New pods created, cutover when healthy | Temporarily doubles resources |
| `ManuallyPromote` | New pods created, waits for manual `forcePromote` | Temporarily doubles resources |
| `ImmediatelyPromoteCausingDowntime` | Old pods torn down first | No extra resources, causes downtime |

## Deploying: Quick Start

Each cloud follows the same pattern:

```bash
git clone https://github.com/MaterializeInc/materialize-terraform-self-managed.git
cd materialize-terraform-self-managed/<cloud>/examples/simple

# Create terraform.tfvars with required variables (see below)
terraform init
terraform apply
```

### Variables by Cloud

**AWS** (`aws/examples/simple/`):
```hcl
name_prefix = "my-mz"                # required
aws_profile = "my-profile"            # required
license_key = "your-license-key"      # required
tags        = { environment = "dev" } # required (no default)
aws_region  = "us-east-1"            # optional, defaults to us-east-1
```

**Azure** (`azure/examples/simple/`):
```hcl
subscription_id     = "12345678-..."   # required
resource_group_name = "materialize-rg" # required
name_prefix         = "my-mz"         # required
tags                = { environment = "dev" } # required (no default)
location            = "westus2"        # optional, defaults to westus2
license_key         = "your-key"       # optional (null default), needed for production
```

**GCP** (`gcp/examples/simple/`):
```hcl
project_id  = "my-gcp-project"        # required
labels      = { environment = "dev" }  # required (no default)
license_key = "your-license-key"      # optional (null default), needed for production
name_prefix = "my-mz"                # optional, defaults to "materialize"
region      = "us-central1"           # optional, defaults to us-central1
```

### Common Optional Variables (all clouds)

| Variable | Default | Purpose |
|----------|---------|---------|
| `internal_load_balancer` | `true` | Set `false` for internet-facing LB |
| `ingress_cidr_blocks` | `["0.0.0.0/0"]` | Restrict access to Materialize ports |
| `k8s_apiserver_authorized_networks` | varies | Restrict K8s API access |
| `crd_version` | `v1alpha1` | Use `v1` for v26.30+ |
| `enable_observability` | `false` | Install Prometheus + Grafana |

## Connecting After Deployment

**Ports:**
- 6875: PostgreSQL-compatible SQL
- 6876: HTTP API
- 8080: Materialize Console (HTTPS)

**AWS** (uses NLB DNS):
```bash
open "https://$(terraform output -raw nlb_dns_name):8080/materialize"
psql "postgres://mz_system@$(terraform output -raw nlb_dns_name):6875/materialize"
```

**Azure / GCP** (uses load balancer IPs):
```bash
open "https://$(terraform output -raw console_load_balancer_ip):8080/materialize"
psql "postgres://mz_system@$(terraform output -raw balancerd_load_balancer_ip):6875/materialize"
```

Use the `external_login_password_mz_system` output for the password when authentication is enabled. Create dedicated users after initial setup; avoid using `mz_system` for regular operations.

## Upgrading Materialize

1. Upgrade one minor version at a time for versions before v26. From v26+ you can skip minor versions.
2. Downgrading is not supported.
3. Upgrade order: operator first, then instances.

**With Terraform:**
Update `environmentd_version` (and optionally `operator_version`) in your variables, then `terraform apply`. For v1alpha1, also update `request_rollout` to a new UUID.

## Instance Sizing

Materialize nodes should use memory-optimized instances with NVMe local storage for swap:

| Cloud | Instance Type | vCPUs | Memory | Max cluster size |
|-------|---------------|-------|--------|------------------|
| AWS | r7gd.2xlarge | 8 | 64 GiB | ~300cc |
| AWS | r7gd.4xlarge | 16 | 128 GiB | ~600cc |
| AWS | r7gd.8xlarge | 32 | 256 GiB | ~1200cc |
| AWS | r7gd.16xlarge | 64 | 512 GiB | ~3200cc |
| Azure | Standard_E4pds_v6 | 4 | 32 GiB | varies |
| GCP | n2-highmem-8 | 8 | 64 GiB | varies |

ARM-based CPUs with a 1:8 vCPU-to-memory ratio and 8:1 local-storage-to-memory ratio are recommended.

## Common Gotchas

- **ECR auth conflicts**: If `terraform apply` fails with 403 pulling public images, run `docker logout public.ecr.aws` and retry.
- **GCP APIs**: You must enable multiple GCP APIs before running Terraform (container, compute, sqladmin, servicenetworking, iamcredentials, iam, storage).
- **Azure preview feature**: Register `EnableAPIServerVnetIntegrationPreview` before deploying on Azure.
- **Self-signed certs**: The simple examples use self-signed TLS. For production, use a real CA or ACME issuer. When using a public ACME issuer (like Let's Encrypt), set `internal_issuer_ref` separately because public CAs cannot sign `*.cluster.local` names.
- **statement_timeout**: The metadata backend URL must include `statement_timeout=15min` or metadata operations may time out.
- **Console slow loads**: If the Console UI is slow, increase `mz_catalog_server` cluster size from 25cc to 50cc via internal SQL port 6877.

## Testing

The test harness in `test/` uses Rust and runs full lifecycle tests (init, apply, verify, destroy):

```bash
cd test
cargo run -- run aws --owner "Name" --license-key-file key.txt \
  --aws-region us-east-1 --aws-profile my-profile
```

Verification checks: Materialize CR status is `UpToDate`, all pods (environmentd, console, balancerd, clusterd) are Running, and `SELECT 1` succeeds over SQL.
