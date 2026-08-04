# Migration Guide: GCP Terraform Module

Migrate from the old `gcp-old/` monolithic module to the new `materialize-terraform-self-managed` modular approach (`gcp/modules/*` + `kubernetes/modules/*`).

> **Important:** This migration example is a **starting point**, not a turnkey solution. Every deployment is different — your VPC layout, node pool sizing, machine types, database configuration, and custom modifications all affect the migration. **You are expected to review and adapt both `main.tf` and `auto-migrate.py` to match your specific infrastructure before running anything.** Always use `--dry-run` first, carefully inspect `terraform plan` output, and never apply changes you don't understand. The migration script modifies Terraform state, which is difficult to undo if done incorrectly.
>
> **Limitations:** This migration supports **single Materialize instance** deployments. If your old configuration defines multiple `materialize_instances`, you'll need to adapt `main.tf` and `auto-migrate.py` manually. This migration also tightens the Google provider version constraint from `>= 6.0` to `>= 6.31, < 7`.

## Quick Start

**Prerequisites:** Terraform CLI (>= 1.8), Python 3.7+, gcloud CLI, kubectl, access to your old Terraform state

```bash
# CRITICAL: Verify old state access first
cd /path/to/old/terraform
terraform state pull | jq '.resources | length'
# Must show 25+ resources

# Setup
cp -r gcp/examples/migration /path/to/new/terraform
cd /path/to/new/terraform
chmod +x auto-migrate.py

# Configure: copy and edit terraform.tfvars
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars to match your existing infrastructure:
#   - REQUIRED: project_id, prefix, license_key
#   - REQUIRED: materialize_instance_name, materialize_instance_namespace
#   - REQUIRED: database_password
#   - INFRA: region, subnet CIDRs, node pool sizing

# Initialize
terraform init

# Test migration (dry-run)
./auto-migrate.py /path/to/old/terraform . --dry-run

# Run migration
./auto-migrate.py /path/to/old/terraform .

# Verify and apply
terraform plan
terraform apply

# Health check
kubectl get materialize -A
terraform output load_balancer_details
```

**Expected Results:**
- **Dry-run**: ~25-35 resources total, ~20+ moved, ~5-8 skipped (data sources, cert-manager manifests due to provider type change), 0 failed
- **Terraform plan**: ~4-6 additions (self-signed cert `kubectl_manifest` resources, materialize instance `kubectl_manifest`, load balancer firewall rules), some minor updates
- **Preserved**: GKE cluster, Cloud SQL instance, VPC, GCS bucket, all Materialize instances

## Migration Checklist

Track your progress:

- [ ] **Prerequisites** - Verify Terraform version, state access, backup current state
- [ ] **Prepare** - Copy migration example, configure terraform.tfvars
- [ ] **Customize terraform.tfvars** - Set all required variables (see `terraform.tfvars.example`)
- [ ] **Review main.tf and auto-migrate.py** - Verify they match your infrastructure; adapt if you have custom modifications
- [ ] **Dry Run** - Test with `--dry-run`, review output carefully, verify 0 failures
- [ ] **Migrate State** - Run auto-migrate.py (handles state moves between old and new)
- [ ] **Verify Plan** - Check terraform plan shows only safe changes
- [ ] **Apply** - Run terraform apply
- [ ] **Health Check** - Verify Materialize is running and accessible
- [ ] **Cleanup** - Remove `.migration-work/` after verification

## Critical: State Access Requirement

**The migration script requires access to your old Terraform state.** It cannot migrate infrastructure that isn't in state.

**Verify before migration:**
```bash
cd /path/to/old/terraform
terraform state pull | jq '.resources | length'
# Should show 25+ resources
# If <10, your state isn't accessible
```

**Common issues:**
- **Remote backend not configured**: State is in GCS or Terraform Cloud but no backend config in directory
  - Fix: Ensure backend configuration in `backend.tf` or `versions.tf`
- **Not initialized**: Old directory needs `terraform init`
- **Wrong directory**: Pointing to module source instead of deployment directory
- **State migrated elsewhere**: Reconfigure old directory to point to actual backend

**What happens with incomplete state:**
- Migration fails with validation error (safety check)
- If bypassed, terraform apply attempts to create all resources
- Results in "already exists" errors everywhere

## Configuring terraform.tfvars

All migration configuration is done via `terraform.tfvars`. Copy `terraform.tfvars.example` and update the values to match your existing infrastructure. You should **not** need to edit `main.tf`.

See `terraform.tfvars.example` for the full list with inline documentation and gcloud/kubectl commands to discover each value.

**Required variables** (no defaults - must be set):

| Variable | Description | How to Find |
|----------|-------------|-------------|
| `project_id` | GCP project ID | `gcloud config get-value project` |
| `prefix` | Prefix used for all resource names | If your GKE cluster is `mycompany-gke`, prefix is `mycompany` |
| `license_key` | Materialize license key | From your old config or https://materialize.com/register |
| `materialize_instance_name` | Your Materialize instance name | `kubectl get materialize -A -o jsonpath='{.items[0].metadata.name}'` |
| `materialize_instance_namespace` | Your Materialize instance namespace | `kubectl get materialize -A -o jsonpath='{.items[0].metadata.namespace}'` |
| `database_password` | Existing Cloud SQL password | From your old `terraform.tfvars` (`database_config.password`) |

**Infrastructure variables** (have defaults matching old module - verify they match yours):

| Variable | Default | How to Verify |
|----------|---------|---------------|
| `region` | `us-central1` | `gcloud container clusters list --format="value(location)"` |
| `subnet_cidr` | `10.0.0.0/20` | `gcloud compute networks subnets describe <prefix>-subnet --region=<region> --format="value(ipCidrRange)"` |
| `database_tier` | `db-custom-2-4096` | `gcloud sql instances describe <prefix>-pg --format="value(settings.tier)"` |
| `database_version` | `POSTGRES_15` | `gcloud sql instances describe <prefix>-pg --format="value(databaseVersion)"` |
| `environmentd_version` | `null` (see note) | `kubectl get materialize -A -o jsonpath='{.items[0].spec.environmentdImageRef}'` (extract version tag) |

**Important:** `environmentd_version` defaults to `null`. If not set, the module uses its built-in default version (v26.7.0), which may not match your running version. **Set this to your current version tag** (e.g., `v0.130.0`).

**Data-path critical variables** - getting these wrong means Materialize won't find its existing data:
- `database_password` - used in `metadata_backend_url` to connect to the existing Cloud SQL
- `materialize_instance_name` - used as the Materialize instance name
- `database_name` - used in `metadata_backend_url` (default: `materialize`)
- `prefix` - used to construct GCS bucket name (`<prefix>-storage-<project_id>`)

## What Changed: Old vs New Module

| Aspect | Old Module | New Module | Migration Impact |
|--------|-----------|------------|------------------|
| **Structure** | Monolithic (`gcp-old/`) | Modular (`gcp/modules/*` + `kubernetes/modules/*`) | State paths change |
| **Terraform** | `>= 1.0` | `>= 1.8` | Terraform version bump |
| **Google Provider** | `>= 6.0` | `>= 6.31, < 7` | Tighter version constraint |
| **Networking** | Direct resources (VPC, subnet, route) | `terraform-google-modules/network/google` + Cloud NAT | Migration keeps old resources inline |
| **GKE** | Basic cluster + system node pool | Adds private_cluster_config, master_authorized_networks, L4 LB subsetting | Migration keeps old config inline |
| **Database** | Direct Cloud SQL resources | `terraform-google-modules/sql-db/google//modules/postgresql` | Migration keeps old resources inline |
| **Storage** | Direct GCS resources | Identical to old | No change |
| **Nodepool** | Same resources, `disk_setup_name = "${prefix}-disk-setup"` | Same resources, `disk_setup_name = "disk-setup"` | Kubernetes disk setup resources recreated with shorter names |
| **Certificates** | `module.certificates` with `kubernetes_manifest` | `cert_manager` + `self_signed_cluster_issuer` with `kubectl_manifest` | Module rename, cert manifests recreated |
| **Operator** | External GitHub source with `count` (`module.operator[0]`) | Local module without count (`module.operator`) | `[0]` index removed |
| **Instances** | Managed by operator module | Separate `materialize-instance` module | Namespace + secret moved |
| **Load Balancers** | `for_each` on instances, no firewall rules | Direct call (single instance), adds firewall rules | `for_each` key removed, firewalls added |
| **CoreDNS** | Not managed | Optional module (replaces kube-dns) | Commented out in migration |
| **Disk setup image** | `v0.4.0` | `v0.4.1` | Pinned to old version in migration |

Most changes are state path updates (no infrastructure changes). Resources with provider type changes (`kubernetes_manifest` to `kubectl_manifest`) are skipped during state migration and created fresh — `kubectl apply` adopts the existing Kubernetes resources with zero disruption.

**Why inline resources?** The new networking module uses `terraform-google-modules` which wraps resources in nested modules (different state paths). The new GKE module adds `private_cluster_config` and L4 LB firewall settings. The new database module uses `terraform-google-modules/sql-db`. To avoid destructive changes, the migration config defines these resources inline with the exact old configuration.

## How Auto-Migration Works

The `auto-migrate.py` script:

1. **Validates state access** - Ensures old state has actual infrastructure (25+ resources)
2. **Analyzes structure** - Auto-detects if you wrapped the module (e.g., `module "mz" { ... }`)
3. **Applies transformation rules**:
   - Moves networking from module to root: `module.networking.*` → `*`
   - Moves GKE from module to root: `module.gke.*` → `*`
   - Renames GKE system node pool: `module.gke.google_container_node_pool.primary_nodes` → `google_container_node_pool.system`
   - Moves database from module to root: `module.database.*` → `*`
   - Keeps materialize nodepool paths unchanged
   - Keeps storage module paths unchanged (identical resources)
   - Renames certificates: `module.certificates.*` → `module.cert_manager.*`
   - Removes `[0]` from operator: `module.operator[0].*` → `module.operator.*`
   - Moves instance resources to `module.materialize_instance.*`
   - Removes `for_each` from load balancers: `module.load_balancers["name"].*` → `module.load_balancers.*`
   - Skips all data sources (automatically recreated)
   - Skips `kubernetes_manifest` resources (recreated as `kubectl_manifest`)
4. **Validates migrated state** (read-only check for potential issues)
5. **Migrates resources** - Uses `terraform state mv` between local state files
6. **Pushes updated states** - Updates both old and new remote backends

**Work files** (in `.migration-work/`):
- `old-state-backup-TIMESTAMP.tfstate` - Original backup for emergency restore
- `old.tfstate`, `new.tfstate` - Working copies
- Never modifies original state files directly

## Expected Changes After Migration

**Additions** (new resources that adopt existing Kubernetes objects):
1. **3 self-signed cert resources** (`kubectl_manifest`) - Adopts existing cert-manager K8s resources (self-signed issuer, root CA certificate, root CA cluster issuer)
2. **1 materialize instance** (`kubectl_manifest`) - Adopts existing Materialize CRD instance
3. **2 firewall rules** (`google_compute_firewall`) - Health check and external ingress rules for load balancers (new in load_balancers module)

**Safe updates** (no infrastructure replacement):
1. **Nodepool disk setup resources** - Namespace, daemonset, SA, RBAC names change from `${prefix}-mz-swap-disk-setup` to `disk-setup` (old resources destroyed, new ones created — swap continues working on existing nodes)
2. **Backend secret** - Updated if backend URL format changes
3. **Operator helm release** - Helm values updated with new structure (license key checks, node selectors, etc.)

**Preserved** (no replacement):
- GKE cluster (no private_cluster_config, no L4 LB settings changes)
- Cloud SQL instance (same `{prefix}-pg` naming)
- VPC, subnet, route, VPC peering
- GCS bucket, HMAC keys
- Materialize node pool (GCP resource)
- Operator and cert-manager helm releases
- All Materialize instances and data

**STOP if you see these being destroyed:**
- GKE Cluster (`google_container_cluster.primary`)
- Cloud SQL Instance (`google_sql_database_instance.materialize`)
- GCS Bucket (`module.storage.google_storage_bucket.materialize`)
- HMAC Key (`module.storage.google_storage_hmac_key.materialize`)
- Service Accounts (`google_service_account.gke_sa`, `google_service_account.workload_identity_sa`)
- Materialize instances

If critical infrastructure is being destroyed, verify your `terraform.tfvars` values match your existing infrastructure.

## Post-Migration: Optional Improvements

After migration is verified and stable, you can gradually adopt new module features:

- **Switch to new networking module** — Uses terraform-google-modules with Cloud NAT for private nodes
- **Switch to new GKE module** — Adds private cluster config, master authorized networks, L4 LB subsetting
- **Switch to new database module** — Uses terraform-google-modules/sql-db with more configurable options
- **Uncomment CoreDNS module** — Replace GKE's kube-dns with zero-TTL CoreDNS
- **Add node taints** on the Materialize node pool for workload isolation
- **Add node selectors** to operator and cert-manager for scheduling control
- **Update disk setup image** — Change `disk_setup_image` from `v0.4.0` to `v0.4.1` (or remove pin)

## Troubleshooting

| Problem | Solution |
|---------|----------|
| State pull fails | Check GCP credentials (`gcloud auth application-default login`), backend config, run `terraform init` in old directory |
| "Only X resources" error (X < 10) | Old state not accessible — verify backend configuration |
| Provider version mismatch | Old module uses `google >= 6.0`, new uses `>= 6.31, < 7`. Run `terraform init -upgrade` in new directory |
| GKE cluster being recreated | Verify inline `main.tf` has no `private_cluster_config` block and no `disable_l4_lb_firewall_reconciliation` |
| Cloud SQL being recreated | Verify `prefix` matches your existing deployment (produces `{prefix}-pg` name) |
| Helm releases timing out | Remove from state: `terraform state rm 'module.operator.helm_release.materialize_operator'` etc. See [Helm Releases](#helm-releases-timing-out) |
| Materialize can't find data | Verify `database_password`, `database_name`, `prefix`, and `materialize_instance_name` in `terraform.tfvars` |
| TLS errors after migration | Verify `use_self_signed_cluster_issuer` matches old module setting |
| Plan shows environmentd version change | Set `environmentd_version` in terraform.tfvars to your current version tag |
| Node pool labels change | Verify `labels` in terraform.tfvars does NOT include `managed_by` or `module` — these are added automatically by `local.common_labels` |
| Disk setup resources being recreated | Expected: namespace/daemonset names change from `${prefix}-mz-swap-disk-setup` to `disk-setup`. Swap continues working on existing nodes. |
| "already exists" error on firewall rules | Import: `terraform import 'module.load_balancers.google_compute_firewall.health_checks' 'projects/<project>/global/firewalls/<name>'` |
| Plan shows too many destroys | Review `terraform.tfvars` values, ensure they match existing infrastructure |

**If script fails with "No transformation rule":**
- Your setup has custom resources not in the standard module
- Add custom transformation rules to `auto-migrate.py` (see [Manual Migration](#manual-migration-for-custom-setups))

### Data Path Matching

The most critical part of migration is ensuring Materialize connects to the same data. These values must match exactly:

**metadata_backend_url** (Cloud SQL connection):
```
postgres://user:password@host:5432/DATABASE_NAME?sslmode=disable
```
- `user` = `database_username` variable (default: `materialize`)
- `password` = `database_password` variable (your existing database password)
- `host` = Cloud SQL private IP (preserved via inline resource)
- `DATABASE_NAME` = `database_name` variable (default: `materialize`)

**persist_backend_url** (GCS via S3-compatible API):
```
s3://hmac_access_id:hmac_secret@bucket_name/materialize?endpoint=https%3A%2F%2Fstorage.googleapis.com&region=<region>
```
- HMAC credentials are preserved (storage module is identical)
- Bucket name is `{prefix}-storage-{project_id}` (preserved via correct `prefix` and `project_id`)
- `/materialize` path prefix is hardcoded

### Helm Releases Timing Out

If helm releases (materialize_operator, cert_manager) timeout during `terraform apply`:
- They're already installed and working in your cluster
- Terraform is trying to update them (which is unnecessary)

**Quick fix - Remove from Terraform state:**
```bash
# These helm releases will continue running, but Terraform stops managing them
terraform state rm 'module.operator.helm_release.materialize_operator'
terraform state rm 'module.cert_manager.helm_release.cert_manager'

# Now apply will skip these resources
terraform apply
```

**Why this works:**
- Helm releases are already running and functional
- Removing from state doesn't delete them from Kubernetes
- They'll continue running independently
- You can manage them manually via `helm upgrade` if needed

## Rollback Procedure

**Before terraform apply** (if you need to abort):
```bash
cd /path/to/old/terraform
terraform state push /path/to/new/terraform/.migration-work/old-state-backup-*.tfstate
terraform plan  # Should show no changes
```

**After terraform apply** (if something went wrong):
```bash
cd /path/to/old/terraform
terraform state push /path/to/new/terraform/.migration-work/old-state-backup-*.tfstate
terraform apply  # Restore original configuration
```

**Emergency restore** (if backends are corrupted):
1. Locate backup file: `.migration-work/old-state-backup-TIMESTAMP.tfstate`
2. Push to backend: `terraform state push <backup-file>`
3. Verify: `terraform plan` should match pre-migration state

## Post-Migration Verification

```bash
# 1. Check Terraform state
terraform state list | wc -l
# Should show ~25-30 resources

# 2. Verify Materialize instances
kubectl get materialize -A
# Should show STATUS: running

# 3. Check pods
kubectl get pods -n <materialize-instance-namespace>
# All should be Running or Completed

# 4. Test connectivity
terraform output load_balancer_details
# Use the balancerd_ip to connect:
psql -h <balancerd-ip> -p 6875 -U mz_system -d materialize

# 5. Verify storage
gsutil ls gs://$(terraform output -json storage | jq -r '.name')/
# Should show the materialize/ prefix

# 6. Check Cloud SQL
terraform output database
# Verify instance name matches your existing instance
```

**Success criteria:**
- Auto-migrate.py shows 0 failures
- Terraform plan shows only expected changes (additions for `kubectl_manifest`, firewall rules)
- Terraform apply succeeds
- `kubectl get materialize -A` shows STATUS: running
- Can connect via psql to load balancer endpoint
- Test queries return expected data (verify your tables/views are present)

## Manual Migration (For Custom Setups)

If you've heavily customized the old module or the automated script doesn't work, you can:

### Option 1: Customize the Automated Script (Recommended)

Add custom transformation rules to `auto-migrate.py` for your modifications:

```python
# In _build_rules() method, add your rules FIRST (before default rules)

# Example: Custom module wrapper
MigrationRule(
    pattern=r'^module\.my_wrapper\.module\.materialize\.(.+)$',
    transform=lambda m: m.group(1),  # Remove wrapper
    description="Remove custom wrapper module"
),

# Example: Custom resource to skip
MigrationRule(
    pattern=r'^module\.custom_monitoring\..*$',
    transform=lambda m: None,  # None means skip
    description="Skip custom monitoring resources"
),

# Example: Rename custom module
MigrationRule(
    pattern=r'^module\.my_custom_name\.(.+)$',
    transform=lambda m: f'module.networking.{m.group(1)}',
    description="Rename custom module to networking"
),
```

**Test your rules:**
```bash
./auto-migrate.py /path/to/old/terraform . --dry-run
```

Check output for:
- `No transformation rule` - Add rules for these
- Incorrect transformations - Adjust regex patterns
- Resources that should skip but aren't - Add skip rules

### Option 2: Full Manual Migration

For one-off heavily customized setups where automation isn't practical.

**Manual process:**

```bash
# 1. Inventory resources
cd /path/to/old/terraform
terraform state list > resources.txt

# 2. Create work directory
mkdir migration-work
cd migration-work

# 3. Pull both states
terraform -chdir=../old state pull > old.tfstate
terraform -chdir=../new state pull > new.tfstate

# 4. Backup
cp old.tfstate old-backup.tfstate
cp new.tfstate new-backup.tfstate

# 5. Move resources one by one
terraform state mv -state=old.tfstate -state-out=new.tfstate \
  'module.networking.google_compute_network.vpc' \
  'google_compute_network.vpc'

# Repeat for all resources in resources.txt
# Adjust paths based on transformation rules in auto-migrate.py

# 6. Push updated states
terraform -chdir=../old state push old.tfstate
terraform -chdir=../new state push new.tfstate

# 7. Verify
cd ../new
terraform plan
```

**Reference transformation rules from auto-migrate.py:**
- `module.networking.*` → root level (remove module prefix)
- `module.gke.*` → root level (remove module prefix)
- `module.gke.google_container_node_pool.primary_nodes` → `google_container_node_pool.system` (rename)
- `module.database.*` → root level (remove module prefix)
- `module.materialize_nodepool.*` → keep unchanged
- `module.storage.*` → keep unchanged
- `module.certificates.kubernetes_namespace.cert_manager[0]` → `module.cert_manager.kubernetes_namespace.cert_manager`
- `module.certificates.helm_release.cert_manager[0]` → `module.cert_manager.helm_release.cert_manager`
- `module.operator[0].*` → `module.operator.*` (remove `[0]`)
- `module.operator[0].kubernetes_namespace.instance_namespaces[*]` → `module.materialize_instance.kubernetes_namespace.instance[0]`
- `module.operator[0].kubernetes_secret.materialize_backends[*]` → `module.materialize_instance.kubernetes_secret.materialize_backend`
- `module.load_balancers["name"].*` → `module.load_balancers.*` (remove for_each key)
- Skip all data sources (recreated automatically)
- Skip `kubernetes_manifest` resources (recreated as `kubectl_manifest`)

## Cleanup

**After verifying everything works:**

```bash
# Remove migration work directory
rm -rf .migration-work/

# (Optional) Clean up old Terraform directory
cd /path/to/old/terraform
rm -rf .terraform terraform.tfstate*
```
