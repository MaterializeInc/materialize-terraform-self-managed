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

- Terraform >= 1.10
- Cloud provider credentials configured
- kubectl (for managing Kubernetes resources)
- Appropriate cloud provider CLI tools (aws-cli, az, or gcloud)
- Linux or macOS. Some modules clean up cloud resources through `local-exec`
  provisioners, which Terraform runs with `/bin/sh` — unavailable when
  Terraform runs from Windows directly, since it uses `cmd` there. On Windows,
  run Terraform from WSL (Best-Effort only).

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

### Container Image Repositories

By default the modules pull container images from Docker Hub. Docker Hub enforces
pull rate limits, which can throttle or fail image pulls on larger clusters, so
each image repository can be pointed at a mirror or pull-through cache instead.
Image *tags* stay controlled by the existing version variables — set the
repository without a tag or digest.

| Module | Variable | Default |
|---|---|---|
| `kubernetes/modules/materialize-instance` | `environmentd_image_repository` | `materialize/environmentd` |
| `{aws,azure,gcp}/modules/operator` | `orchestratord_image_repository` | Helm chart default (`materialize/orchestratord`) |
| `kubernetes/modules/coredns` | `coredns_image_repository` | `coredns/coredns` |
| `{aws,azure,gcp}/modules/nodepool`[^dsi] | `disk_setup_image` | `materialize/ephemeral-storage-setup-image:<version>` |

[^dsi]: `aws/modules/eks-node-group` and `aws/modules/karpenter-ec2nodeclass` on AWS. Unlike the others, `disk_setup_image` is a full image reference including the tag.

```hcl
module "materialize_instance" {
  source = "github.com/MaterializeInc/materialize-terraform-self-managed//kubernetes/modules/materialize-instance?ref=<tag>"

  environmentd_image_repository = "myregistry.example.com/materialize/environmentd"
  # ... additional configuration
}
```

Note that the operator derives the `clusterd`, `balancerd`, and `console` image
references from `environmentdImageRef`, reusing everything before the final `/`
as the namespace. Overriding `environmentd_image_repository` therefore redirects
those three images too, but only if the mirror preserves the upstream path
layout — that is, all four images must be reachable as
`<your-prefix>/materialize/<image>`. A pull-through cache of Docker Hub
satisfies this automatically.

Modules that install third-party Helm charts (cert-manager, metrics-server,
Prometheus, Grafana, node-local-dns, and the AWS addons) mostly pull from
registries without rate limits, such as `registry.k8s.io`, `quay.io`, and public
ECR. Where those modules accept a `helm_values` variable, you can override the
chart's own image values to redirect them.

## Upgrading

Most of the time, you just need to bump the `ref=<tag>` in all modules. We recommend that you bump all modules to the same version in the same `terraform apply`. We frequently make changes that assume related changes in dependent modules.

Upgrades of the materialize version are included in our tagged releases. We do not recommend overriding the Materialize version, orchestratord version, or helm chart version. Updating the module tags will automatically pick up the latest versions of these components.

We follow semantic versioning with our tags. If a particular version requires additional actions or contains breaking changes, we will list them below.

### Upgrade Notes

#### v13.0.0

`aws/modules/monitoring` moves its two telemetry buckets into the S3 account regional namespace, which **replaces both of them**. That namespace is house policy for new buckets: the name is reserved to your account, so no other account can take it and none can ever take it back. This is the whole of the release, and it affects every existing AWS deployment of the monitoring stack. Nothing outside `aws/modules/monitoring` changes, and GCP and Azure are untouched.

**Impact on existing AWS deployments:**

- **Both telemetry buckets are replaced.** The name changes shape, from `<prefix>-mzmon-logs-<random>` to `<prefix>-mzmon-logs-<account>-<region>-an`, and a bucket's name forces a new resource. S3 offers no in-place migration between namespaces — AWS's own guidance is to create the new bucket and copy — so copy anything you need to keep first, or stay on `v12` until you have. Nothing else about the buckets changes: regional endpoints, ARNs, IAM resource patterns, and both backends' configuration are the same as before.
- **How that replacement goes depends on `bucket_force_destroy`, which the module defaults to `false`.** On the default the apply **fails** with `BucketNotEmpty` and both buckets and their contents survive — S3 will not delete a non-empty bucket, and the module would rather stop than discard telemetry nobody said could go. Note that versioning is on by default, so a bucket whose objects have all expired still holds noncurrent versions and delete markers and is not empty. Expect the failure partway through: a replaced bucket's dependents are destroyed ahead of the bucket, so the surviving buckets can be left without their public-access block, encryption, versioning, and lifecycle configuration, and re-running plans the same replacement and fails the same way. To get through it, either set `bucket_force_destroy = true` and accept that **every Loki log and Thanos metric in the buckets is lost**, or empty the buckets yourself once you have copied what you need. The examples already pass `true`, matching their throwaway posture; a root of your own on the default has to choose.
- **The module takes a new required `account_id` variable.** Pass `data.aws_caller_identity.current.account_id` from the root of your configuration, as the examples now do. It is part of the bucket name, and it has to be resolved at the root: the examples put a `depends_on` on this module call, and a module-level `depends_on` defers every data source inside the module to apply time, which would leave the bucket name unknown at plan — and an unknown bucket name is a bucket replacement on every subsequent apply, not just this one.
- **Keep `name_prefix` to 18 characters or fewer.** The account regional suffix takes 31 of the 63 characters S3 allows a bucket name, against the 8 the random suffix took, so the room left for the prefix drops from 40 to 18 — 23 in the shortest region codes, 18 in the longest, so 18 is the number that holds everywhere. A prefix too long for the name is refused at plan time rather than by the S3 API mid-apply. Note that `name_prefix` is shared with the other AWS modules, so shortening it renames a great deal more than the buckets; if that is not something you can do, stay on `v12`.
- **`aws/modules/monitoring` now floors the `hashicorp/aws` provider at `6.37.0`** (`~> 6.37`), the release that added `bucket_namespace`. `terraform init -upgrade` covers it; the other AWS modules keep the `~> 6.0` they picked up in v12.0.0.
- **Deployments in `me-south-1` and `me-central-1` are unaffected.** AWS does not offer account regional namespaces there, so those two regions keep the global namespace and the random suffix, and their buckets are not replaced. If AWS adds support later, adopting it in those regions will be the same breaking change this note describes.

#### v12.0.0

The AWS modules now require the `hashicorp/aws` provider `~> 6.0` (previously `~> 5.0`). The EKS modules moved from `terraform-aws-modules/eks` v20 to v21, which requires provider 6.x and no longer bootstraps the self-managed `aws-node`, `kube-proxy`, and CoreDNS addons on new clusters. Everything the cluster previously inherited from that bootstrap is now managed explicitly: `kube-proxy` as an EKS addon, the `aws-node` service account by the VPC CNI Helm chart, and the CoreDNS service account, RBAC, and `kube-dns` Service by the coredns module.

**Required changes for existing AWS deployments** (in order):

1. **Update your configuration** to match the new example wiring:
   - Pass the new eks-node-group `partition` and `account_id` variables, from `aws_partition` and `aws_caller_identity` data sources at the root of your configuration, as the examples now do. See "Reviewing the plan" below for why this matters.
   - Set `create_coredns_service_account = true`, `create_kube_dns_service = true`, and `kube_dns_service_cluster_ip` on the coredns module, as the examples now do.
   - If your root has other constraints capping `hashicorp/aws` below 6.x, raise them.
2. **Run `terraform init -upgrade`** to install the 6.x provider and the v21 EKS module.
3. **Import the bootstrapped `kube-dns` Service into state** (clusters created with earlier versions of these modules have one; the coredns module now manages it):

   ```sh
   terraform import 'module.coredns.kubernetes_service.kube_dns[0]' kube-system/kube-dns
   ```

   This import path matches our examples. Your path may be different depending on where your coredns module is instantiated.

   Skipping this fails at apply. The API server allocates the ClusterIP before it detects the name collision, so which error you get depends on the existing Service: `failed to allocate IP <addr>: provided IP is already allocated` when it holds the address this module asks for, which is the usual case since both use the 10th address of the service CIDR, and `Service "kube-dns" already exists` when it holds a different one.
4. **Run `terraform plan`, review it against the notes below, then apply.**

**Reviewing the plan:**

- Expected changes: the `kube-proxy` EKS addon (adopts the existing self-managed kube-proxy), the CoreDNS service account and RBAC, a node security-group rule for port 10251, removal of the module's `terraform-aws-modules` tag and of a redundant cluster-encryption IAM policy (the KMS key policy retains the cluster grant), and in-place updates to the coredns and VPC CNI releases.
- **The imported `kube-dns` Service shows an in-place update.** The module narrows the Service selector to the pods it owns, adding `provisioned-by = "materialize"`, and drops any platform-specific labels it does not declare. Narrowing the selector is what moves cluster DNS off the platform CoreDNS and onto `coredns-custom`, which the provisioner then scales to zero. Confirm `coredns-custom` is already serving before you apply, since it becomes the only endpoint behind the cluster DNS address:

  ```sh
  kubectl -n kube-system get pods -l provisioned-by=materialize
  ```

- **No node group or launch template changes are expected.** The eks-node-group module pins the v20 launch-template defaults (AMI release tracking, IMDS hop limit 2, detailed monitoring) precisely so this upgrade does not roll your nodes. If your plan shows node groups or launch templates being replaced, stop and investigate before applying.
- **No `aws_iam_role_policy_attachment` replacements are expected.** If the plan shows them with `policy_arn = (known after apply)`, do not apply it — that replacement silently detaches the managed policies from the live node role (the create is an AWS no-op, the deposed destroy detaches). It means the `partition`/`account_id` variables from step 1 are not reaching the node group module: the examples put a `depends_on = [module.vpc_cni]` on the node group call (so new clusters have a CNI before nodes boot), and a module-level `depends_on` defers every data source inside the module to apply time whenever the depended-on module has pending changes — without the two variables, the upstream module's own partition lookup is deferred and the policy ARNs derived from it become unknown. If you have already applied such a plan, run plan and apply again to re-attach the policies.

**Behavior notes (no action needed):**

- The coredns deployment rolls onto a new `coredns-custom` service account. This is a rolling update and the `kube-dns` Service selects old and new pods alike, so DNS stays up throughout.
- The networking module moves from `terraform-aws-modules/vpc` v5 to v6. That major exists only to require provider 6.x — no inputs were renamed and no outputs removed — so no VPC, subnet, or endpoint changes are expected in the plan.
- This crosses the aws provider 5.x → 6.x major version boundary. The modules in this repository do not use any of the fields removed in 6.0, but if you manage additional AWS resources in the same configuration, review the [aws provider 6.0 upgrade guide](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/guides/version-6-upgrade) for changes affecting them.

**Impact on existing GCP deployments:**

- The coredns module's managed service account, cluster role, and binding are renamed from `coredns`/`system:coredns` to `coredns-custom`, so they can never collide with platform-owned objects. The next apply destroys and recreates them under the new names and rolls the coredns deployment onto the new service account.

**Impact on the monitoring stack (all clouds):**

The monitoring stack gains in-cluster TLS, on by default. Only `modules/monitoring` and the observability components it installs are affected.

- **cert-manager is now required wherever `enable_observability` is on.** The examples install it; a root of your own must do the same or set `certificates_enabled = false`. With certificates on and the CRDs absent, the apply fails on an unknown `cert-manager.io/v1` kind. A root that calls the module directly also needs `module.cert_manager` in its `depends_on`, or the Helm release races the CRDs.
- **`internal_tls` defaults to `authenticate`, so the stack's own components require client certificates from each other.** Upgrading a running stack, apply `internal_tls = "present"` first and let it settle: Kubernetes does not order a server's rollout against its clients', and a one-step cutover drops telemetry on any hop whose server pod rolls first. A new deployment can go straight to the default.
- **Anything outside the chart that writes to the Alloy gateway must present a client certificate** — an application remote-writing metrics to `9090`, or sending OTLP to `4317`/`4318`, is refused at the TLS handshake. Park at `internal_tls = "present"` while you roll certificates out to those senders, or `"encrypt"` if they cannot present one at all.
- Bring your own PKI with `internal_issuer_ref`; left unset, the chart bootstraps a root scoped to the monitoring release. See each cloud's `modules/monitoring/README.md` for the new inputs, and [Securing the stack](https://materializeinc.github.io/materialize-monitoring/operating/securing/) for what each phase does and does not buy.

#### v11.0.0

Grafana gains durable state and a way to reach it. Both are opt-out rather than opt-in: the previous release left Grafana on SQLite in an `emptyDir` and reachable only through `kubectl port-forward`, which is fine for a bundled extra and not for the primary interface to the stack.

**Impact on existing deployments:**

- **`enable_observability` now defaults to `true` in the `simple` examples**, matching `enterprise`. The monitoring stack is opt-out rather than opt-in: bumping `ref=<tag>` on a `simple` root that never set the variable installs the whole stack — Loki, Thanos, Grafana, Alertmanager, kube-state-metrics, Alloy — along with its object storage and cloud identities. Set `enable_observability = false` to keep it off. The `generic` node pool may need to grow to fit it; see the v10.0.0 note below for what the stack runs.
- Two new billable resources per deployment, **created whenever `enable_observability` is on**: the smallest PostgreSQL instance the cloud offers (`db.t4g.micro`, `db-f1-micro`, `B_Standard_B1ms`) and an internal L4 load balancer. With observability now defaulting on everywhere, bumping `ref=<tag>` creates both on `simple` and `enterprise` alike unless you turn it off.
- The database holds Grafana's own state — users, service accounts and API tokens, annotations, dashboard versions, preferences. Set `grafana_database = null` on the monitoring module block to skip it and keep the previous SQLite behaviour, or point at a database you already run with `grafana_database_host` and friends. **Switching to it does not carry existing state over**; Grafana has no SQLite-to-PostgreSQL migration, so export anything you care about through its HTTP API first.
- The load balancer is internal by default, and allowlisted to `ingress_cidr_blocks`. Going public needs `internal_load_balancer = false`, and a public load balancer whose allowlist is still `0.0.0.0/0` is **refused at plan time** for Grafana specifically.
- Nothing terminates TLS, and Grafana has no identity provider until you configure one, so the generated admin password is the whole of the access control. Treat it as internal-only until both are addressed. Do not set `security.cookie_secure` in the meantime: it marks the session cookie `Secure`, the browser then stops sending it over the plain-HTTP connection that works, and login breaks entirely.
- `grafana_url` keeps its name; its meaning becomes conditional. It is the hostname you supplied, else the load balancer's address, else the in-cluster Service. Nothing here publishes DNS for a hostname you supply.
- **AWS only:** `aws/modules/monitoring` now requires the `alekc/kubectl` provider, for the `TargetGroupBinding` that attaches its NLB to the Grafana Service. The examples already configure it; a root that calls the module directly must add it, and also now supplies `vpc_id`, `subnet_ids`, and `node_security_group_id` inside `grafana_load_balancer`.
- **AWS only: the Grafana NLB is replaced, and its DNS name changes.** The load balancer's name is now generated from a short prefix rather than derived from `name_prefix`, because a derived name is capped at 32 characters and collides between two deployments whose prefixes agree in their first 18 (`materialize-staging-blue` and `-green` both produced `materialize-stagin-mzmon-grafana`). Anyone already reaching Grafana through the v11.0.x NLB gets a **new address** on this bump: repoint any DNS record or `grafana_host` that names the old one. Set `grafana_nlb_name` to pin a specific name instead — at the cost of `create_before_destroy`, so replacements become a short outage.
- New outputs: `grafana_load_balancer_address`, `grafana_database_endpoint`, and `grafana_database_password` on all three clouds, plus `grafana_load_balancer_arn` and `grafana_load_balancer_security_group_id` on AWS.

See each cloud's `modules/monitoring/README.md` for the full input and output list, and [Reaching Grafana](https://materializeinc.github.io/materialize-monitoring/getting-started/terraform/#reaching-grafana) for why the load balancers are L4 and what moving to L7 would take.

#### v10.0.0

We have introduced a new observability stack that replaces the previous Prometheus + Grafana stack. The new stack is cloud-native and supports logs, metrics, and dashboards.

`kubernetes/modules/prometheus` and `kubernetes/modules/grafana` are replaced by `aws/modules/monitoring`, `gcp/modules/monitoring`, and `azure/modules/monitoring`, which install the [`materialize-monitoring`](https://github.com/MaterializeInc/materialize-monitoring) charts. The two legacy modules are **removed**, not deprecated in place. If you referenced `kubernetes/modules/prometheus` or `kubernetes/modules/grafana` directly rather than through an example, that reference breaks on this version — pin the previous major until you have migrated to the monitoring module for your cloud.

The old stack vendored a point-in-time dashboard copy and a legacy scrape config, collected metrics only, and ran a single Prometheus on a `ReadWriteOnce` volume with 15 days of retention. The new one adds logs (Loki), object-storage-backed metrics (Thanos), alerting, and the Alloy collection pipeline, and gets its dashboards and scrapers from released chart artifacts rather than copies.

**Impact on existing deployments:**

- The `prometheus` and `grafana` Helm releases and their PersistentVolumeClaims are **destroyed**. Up to 15 days of local Prometheus data goes with them — there is no backfill, and the new stack begins collecting at install. Anything hand-created in the old Grafana (dashboards, users, saved queries) does not carry over.
- The `prometheus_url` output is gone, replaced by `metrics_url` (Thanos Query) and `logs_url` (Loki). Thanos Query is Prometheus-API-compatible, so consumers of the old URL work against the new one — only the host and port change.
- `grafana_url` and `grafana_admin_password` keep their names and meaning. Grafana remains `ClusterIP`, so reaching it is still `kubectl -n monitoring port-forward svc/grafana 3000:80`.
- New cloud resources are created: storage for each backend (logs and metrics) plus a per-backend cloud identity bound to the in-cluster ServiceAccount.
  - **AWS** — an S3 bucket and an IRSA role per backend.
  - **GCP** — a GCS bucket and a Google service account per backend, bound with `roles/iam.workloadIdentityUser`. Requires Workload Identity on the cluster, which the `gke` module already sets.
  - **Azure** — one storage account with a blob container per backend, a user-assigned managed identity per backend holding `Storage Blob Data Contributor` scoped to its own container, and a federated identity credential per ServiceAccount. Requires both `oidc_issuer_enabled` and `workload_identity_enabled` on the cluster, which the `aks` module already sets. The account is created with `shared_access_key_enabled = false`, so nothing falls back to a shared key.
- Node pool capacity: the new stack runs microservice Loki, Thanos, Grafana, Alertmanager, kube-state-metrics, and two Alloy roles, against the previous stack's single Prometheus and Grafana. The `generic` pool may need to grow, or the first apply lands unschedulable pods.
- If you set `install_metrics_server = false` on the operator module, set `install_metrics_server = true` on the monitoring module in the same change — the Materialize Console depends on the metrics API for cluster metrics.
- **Azure only:** the Entra Workload ID webhook only mutates pods labelled `azure.workload.identity/use: "true"`, and the monitoring module applies that label for you. It reaches Thanos through `global.commonLabels` rather than a `podLabels` the Thanos chart does not have, so the label also appears on Thanos object metadata. That is cosmetic — it is not in any workload selector, so it is safe on an existing install.

`enable_observability` keeps its name and its defaults (`false` in `simple`, `true` in `enterprise`).

#### v9.0.0

The `materialize-instance` module now enables role-based access control by default. A new `enable_rbac` variable (bool, default `true`) sets `spec.enableRbac` on the Materialize CR. Previously the module never set the field, so it fell back to the CRD default (`false`) and the operator launched environmentd with `enable_rbac_checks=false`, meaning privilege checks were not enforced.

**Impact on existing deployments:**

- Bumping `ref=<tag>` turns on privilege checks for existing instances. Any role that was relying on unenforced privileges loses access until it is granted the privileges it needs. `mz_system` remains a superuser, so bootstrap and admin automation running as `mz_system` is unaffected.
- Review the grants for your application roles before applying. See [Access control](https://materialize.com/docs/security/self-managed/access-control/) and [`GRANT PRIVILEGE`](https://materialize.com/docs/sql/grant-privilege/) for the privileges each object type requires.
- To keep the previous behavior, set `enable_rbac = false` on the `materialize-instance` module.

The GCP examples now default `region` to `us-east1` (previously `us-central1`), for capacity availability. This affects the `region` variable defaults in `gcp/examples/simple` and `gcp/examples/enterprise`. `gcp/examples/migration` deliberately keeps `us-central1`, because its `region` describes an existing deployment being adopted into new state rather than where new deployments should go. The reusable `gcp/modules/*` take `region` as a required input and are unchanged.

**Impact on existing deployments:**

- **If you deployed the simple or enterprise GCP example without setting `region`, you must now set it explicitly to `us-central1` before upgrading.** Otherwise the new default applies and `terraform plan` will show a destructive, data-losing teardown and recreation of every regional resource in `us-east1`:

  ```hcl
  region = "us-central1"
  ```

  After setting it, confirm `terraform plan` reports no changes to regional resources.
- Regional resources that are replaced: the GKE cluster and its node pools (the node pools are a separate `nodepool` module, so they are replaced independently of the cluster), the Cloud SQL instance, the GCS bucket, the subnet, and the Cloud Router and Cloud NAT.
- The VPC network itself is **not** replaced — `google_compute_network` is global, as are the `load_balancers` module's firewall rules, the private-services `google_compute_global_address`, and the service networking peering connection. Only the regional resources above churn.
- The load balancers are not region-parameterized in Terraform (the `load_balancers` module has no `region` input; it creates `kubernetes_service` objects of type `LoadBalancer`). They still get new IP addresses, because GKE provisions fresh regional forwarding rules for the Services in the replacement cluster. Repoint any DNS records afterwards — the enterprise example in particular needs its console, balancerd, Hydra, Kratos, and selfservice UI A records updated, and cert-manager cannot issue browser-facing certs until those resolve.
- Pay particular attention to Cloud NAT: recreating it in a new region changes your egress IP addresses, which breaks any downstream allowlists that pin them, and makes any static regional `nat_ips` addresses unusable in the new region.
- If you already pass `region` explicitly (including all consumers of `gcp/modules/*`), there is no impact.
- To actually move an existing deployment to `us-east1`, treat it as a new deployment plus a data migration. GCP cannot relocate these resources in place, so there is no in-place `terraform apply` path between regions.
- `gcp/README.md`'s `node_locations` examples now use `us-east1-b` and `us-east1-d`. `node_locations` must name zones inside the cluster's region. The module only regex-checks the `region-zone` string shape, so copies of the old `us-central1-*` examples pass `terraform validate` and `plan` and then fail at apply from the GKE API. Note `us-east1` has no `-a` zone.

##### Minimum Terraform Version

The default floor of terraform is now 1.10 which was released before 2025-01-01.
This fixes some buggy behavior with source references that contain a `/` in the tag name.
The recommended version remains any stable version of terraform: 1.14 and 1.15 at this time.

#### v8.0.0

The GCP modules now require the `hashicorp/google` provider `>= 7.22, < 8` (previously `>= 6.31, < 6.51.0`). This is required by the upgrade of the upstream `terraform-google-modules/sql-db/google` module to v28, which no longer supports google provider 6.x.

**Impact on existing deployments:**

- `terraform init -upgrade` is required to install the 7.x provider and update your lockfile. If your root module has other provider constraints capping `hashicorp/google` below 7.x, init will fail until those are raised as well.
- This crosses the google provider 6.x → 7.x major version boundary. The modules in this repository do not use any of the fields removed in 7.0, but if you manage additional GCP resources in the same configuration, review the [google provider 7.0 upgrade guide](https://registry.terraform.io/providers/hashicorp/google/latest/docs/guides/version_7_upgrade) for changes affecting them.
- Run `terraform plan` against your existing state before applying and review any unexpected diffs introduced by the provider upgrade.

#### v7.0.0

The GCP `networking` module now requires a list of strings rather than a single string for `var.routes.tags`.

#### v6.0.0

The AWS `karpenter-nodepool` module no longer hardcodes `terminationGracePeriod: 300s` on Karpenter NodePools. A new `termination_grace_period` variable controls it and defaults to `null` (unset).

With a `terminationGracePeriod` set, Karpenter replaces drifted nodes (for example, after changing the node pool's instance types) even when pods carry the `karpenter.sh/do-not-disrupt` annotation — the annotation and PDBs only delay eviction until the node's termination deadline. Materialize instance pods were therefore force-evicted about 5 minutes after any node pool change. With it unset, do-not-disrupt pods block disruption until a Materialize rollout moves them.

The AWS examples now set `termination_grace_period = "300s"` on the generic pool (matching the previously hardcoded value; its workloads tolerate eviction) and leave it unset on the materialize pool.

**Impact on existing deployments:**

Karpenter stamps `terminationGracePeriod` into each NodeClaim when the node is created and never updates it afterwards; changing the NodePool only marks existing nodes as Drifted. Existing materialize nodes were created with `300s` baked in, so the first `terraform apply` that changes the NodePool template (including removing `terminationGracePeriod`) drift-replaces them, and their baked-in deadline bypasses do-not-disrupt one final time. Materialize pods restart with a short interruption.

If a one-time restart of your Materialize instances is acceptable, bump `ref=<tag>` and apply. The replacement nodes are created without `terminationGracePeriod`, and node pool changes from then on respect do-not-disrupt.

To migrate without downtime, keep the old pool's template unchanged and move pods to a new pool first, similar to the GCP node pool migration in v5.0.0:

1. Bump `ref=<tag>` on all modules, and set `termination_grace_period = "300s"` on your existing materialize nodepool module instance. This matches the value the module previously hardcoded, so the NodePool template is unchanged and no nodes drift. Keep the generic pool at `"300s"` (as the examples do) and its nodes don't drift either.
2. `terraform apply`. There should be no changes to the `termination_grace_period` on the node pools.
3. Add a second materialize nodepool module instance with a new `name` (for example `materialize2`), the same `nodeclass_name`, labels, and taints, but `termination_grace_period` should be unset.
4. `terraform init && terraform apply` to create the new NodePool. It has no nodes yet.
5. Prevent the old NodePool from provisioning new nodes by setting `limits = { cpu = "0" }` on the old materialize nodepool module instance. Limits are not part of the NodePool template, so this does not drift the existing nodes.
6. `terraform apply` to cap the old NodePool. Do this before cordoning: if the pool were still uncapped when its nodes are cordoned, any pending pods could cause Karpenter to provision fresh (uncordoned) nodes from the old pool.
7. Cordon the old pool's nodes so the rollout's new pods cannot be scheduled onto them. Cordoning only blocks new scheduling; the pods already running there are unaffected:

   ```bash
   kubectl cordon -l karpenter.sh/nodepool=materialize
   ```
8. Prepare a rollout of your Materialize instances by setting the `force_rollout` field to a new UUID. If you have reverted to the `v1alpha1` version of the Materialize CRD, also set `request_rollout` to the same UUID.
9. `terraform apply` to perform the rollout. The old pool's nodes are cordoned and the pool is capped, so Karpenter provisions capacity from the new pool for the new-generation pods.
10. Verify the new environmentd and clusterd pods are running on the new pool's nodes. Once the old nodes are empty, Karpenter consolidates them away (`WhenEmpty`, after 60s); cordoning does not block this.
11. Remove the old nodepool module instance (with its `termination_grace_period = "300s"` pin and `limits` cap) from your configuration.
12. `terraform apply` to delete the old NodePool.

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
