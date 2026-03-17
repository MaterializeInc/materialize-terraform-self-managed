# Migration Guide: Azure Terraform Module

Migrate from the old `azure-old/` monolithic module to the new `materialize-terraform-self-managed` modular approach (`azure/modules/*` + `kubernetes/modules/*`).

> **Important:** This migration example is a **starting point**, not a turnkey solution. Every deployment is different — your VNet layout, node pool sizing, VM sizes, database configuration, and custom modifications all affect the migration. **You are expected to review and adapt both `main.tf` and `auto-migrate.py` to match your specific infrastructure before running anything.** Always use `--dry-run` first, carefully inspect `terraform plan` output, and never apply changes you don't understand. The migration script modifies Terraform state, which is difficult to undo if done incorrectly.
>
> **Limitations:** This migration supports **single Materialize instance** deployments. If your old configuration defines multiple `materialize_instances`, you'll need to adapt `main.tf` and `auto-migrate.py` manually. This migration also upgrades the azurerm provider from v3 to v4, which may surface additional attribute-level diffs in `terraform plan`.

## Quick Start

**Prerequisites:** Terraform CLI (>= 1.8), Python 3.7+, Azure CLI, kubectl, access to your old Terraform state

```bash
# CRITICAL: Verify old state access first
cd /path/to/old/terraform
terraform state pull | jq '.resources | length'
# Must show 30+ resources

# Setup
cp -r azure/examples/migration /path/to/new/terraform
cd /path/to/new/terraform
chmod +x auto-migrate.py

# Configure: copy and edit terraform.tfvars
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars to match your existing infrastructure:
#   - REQUIRED: subscription_id, name_prefix, license_key, materialize_instance_name
#   - REQUIRED: old_db_password, external_login_password_mz_system
#   - INFRA: location, vnet_address_space, subnet CIDRs, service_cidr
#   - SIZING: node pool VM sizes and min/max node counts
#   - DATABASE: postgres_version, database_sku_name, database_storage_mb

# Test migration (dry-run)
./auto-migrate.py /path/to/old/terraform . --dry-run

# Run migration
./auto-migrate.py /path/to/old/terraform .

# Verify and apply
terraform init
terraform plan
terraform apply

# Health check
kubectl get materialize -A
terraform output load_balancer_details
```

**Expected Results:**
- **Dry-run**: ~30 resources total, ~20+ moved, ~5-8 skipped (data sources, cert-manager manifests due to provider type change, key vault), 0 failed
- **Terraform plan**: ~4-6 additions (self-signed cert `kubectl_manifest` resources, materialize instance `kubectl_manifest`, federated identity credential), some minor updates
- **Preserved**: AKS cluster, PostgreSQL server, VNet, storage account, all Materialize instances

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
- [ ] **Cleanup** - Remove `.migration-work/` after verification, delete old Key Vault manually

## Critical: State Access Requirement

**The migration script requires access to your old Terraform state.** It cannot migrate infrastructure that isn't in state.

**Verify before migration:**
```bash
cd /path/to/old/terraform
terraform state pull | jq '.resources | length'
# Should show 30+ resources
# If <10, your state isn't accessible
```

**Common issues:**
- **Remote backend not configured**: State is in Azure Storage or Terraform Cloud but no backend config in directory
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

See `terraform.tfvars.example` for the full list with inline documentation and Azure CLI commands to discover each value.

**Required variables** (no defaults - must be set):

| Variable | Description | How to Find |
|----------|-------------|-------------|
| `subscription_id` | Azure subscription ID | `az account show --query id -o tsv` |
| `resource_group_name` | Existing resource group name | `az group list --query "[?tags.module=='materialize'].name" -o tsv` |
| `name_prefix` | Prefix used for all resource names | If your AKS cluster is `mycompany-aks`, prefix is `mycompany` |
| `license_key` | Materialize license key | From your old config or https://materialize.com/register |
| `materialize_instance_name` | Your Materialize instance name | `kubectl get materialize -A -o jsonpath='{.items[0].metadata.name}'` |
| `old_db_password` | Existing PostgreSQL database password | From your old `terraform.tfvars` (`database_config.password`) |
| `external_login_password_mz_system` | Existing mz_system user password | From old config (`external_login_password_mz_system`) |

**Infrastructure variables** (have defaults matching old module - verify they match yours):

| Variable | Default | How to Verify |
|----------|---------|---------------|
| `location` | `eastus2` | `az aks show --name <prefix>-aks --resource-group <rg> --query location -o tsv` |
| `vnet_address_space` | `10.0.0.0/16` | `az network vnet show --name <prefix>-vnet --resource-group <rg> --query addressSpace.addressPrefixes[0] -o tsv` |
| `kubernetes_version` | `null` (see note) | `az aks show --name <prefix>-aks --resource-group <rg> --query kubernetesVersion -o tsv` |
| `service_cidr` | `10.1.0.0/16` | `az aks show --name <prefix>-aks --resource-group <rg> --query networkProfile.serviceCidr -o tsv` |
| `database_sku_name` | `GP_Standard_D2s_v3` | `az postgres flexible-server show --name <server> --resource-group <rg> --query sku.name -o tsv` |
| `environmentd_version` | `null` (see note) | `kubectl get materialize -A -o jsonpath='{.items[0].spec.environmentdImageRef}'` (extract version tag) |

**Important:** `kubernetes_version` and `environmentd_version` default to `null`. If not set:
- `kubernetes_version = null` means "latest recommended" — terraform plan may show a Kubernetes version upgrade. **Set this to match your current version.**
- `environmentd_version = null` means the module uses its built-in default (which may not match your running version). **Set this to your current version tag** (e.g., `v0.130.0`).

**Data-path critical variables** - getting these wrong means Materialize won't find its existing data:
- `old_db_password` - used in `metadata_backend_url` to connect to the existing PostgreSQL server
- `materialize_instance_name` - used as the Materialize instance name and in backend URL construction
- `database_name` - used in `metadata_backend_url` (default: `materialize`)

## What Changed: Old vs New Module

| Aspect | Old Module | New Module | Migration Impact |
|--------|-----------|------------|------------------|
| **Structure** | Monolithic (`azure-old/`) | Modular (`azure/modules/*` + `kubernetes/modules/*`) | State paths change |
| **Provider** | azurerm >= 3.75 | azurerm 4.54.0 | Provider upgrade |
| **AKS Network** | `network_plugin=azure`, `network_policy=azure` | New module defaults to `cilium` | Migration keeps old config inline |
| **AKS Outbound** | Default `loadBalancer` | New module uses `userAssignedNATGateway` | Migration keeps old config inline |
| **Networking** | Direct VNet/Subnet resources | New uses Azure Verified Module (AVM) + NAT gateway | Migration keeps old resources inline |
| **Database Naming** | `{prefix}-{random}-pg` | New module uses `{prefix}-pg` | Migration keeps old naming inline |
| **Storage Auth** | SAS tokens via Key Vault | Workload identity via federated credential | SAS tokens dropped, workload identity added |
| **Certificates** | `module.certificates` with `kubernetes_manifest` | `cert_manager` + `self_signed_cluster_issuer` with `kubectl_manifest` | Module rename, cert manifests recreated |
| **Operator** | External GitHub source with `count` (`module.operator[0]`) | Local module without count (`module.operator`) | `[0]` index removed |
| **Instances** | Managed by operator module | Separate `materialize-instance` module | Namespace + secret moved |
| **Load Balancers** | `for_each` on instances | Direct call (single instance) | `for_each` key removed |
| **CoreDNS** | Not managed | Optional module | Commented out in migration |
| **DB Password** | `random_password` resource | Explicit variable (`old_db_password`) | Must provide existing password |
| **TLS Config** | In operator Helm values | Passed via `helm_values` variable | Configured in migration `main.tf` |

Most changes are state path updates (no infrastructure changes). Resources with provider type changes (`kubernetes_manifest` to `kubectl_manifest`) are skipped during state migration and created fresh — `kubectl apply` adopts the existing Kubernetes resources with zero disruption.

**Why inline resources?** The new AKS module hardcodes `outbound_type = "userAssignedNATGateway"` and `network_policy = "cilium"`, both of which force AKS cluster recreation. The new networking module creates a NAT gateway that doesn't exist in old setups. The new database module changes server naming. To avoid destructive changes, the migration config defines these resources inline with the exact old configuration.

## How Auto-Migration Works

The `auto-migrate.py` script:

1. **Validates state access** - Ensures old state has actual infrastructure (30+ resources)
2. **Analyzes structure** - Auto-detects if you wrapped the module (e.g., `module "mz" { ... }`)
3. **Applies transformation rules**:
   - Moves networking from module to root: `module.networking.*` → `*`
   - Moves AKS from module to root: `module.aks.*` → `*`
   - Renames AKS system nodepool: `module.aks.*.materialize` → `*.system`
   - Moves database from module to root: `module.database.*` → `*`
   - Keeps materialize nodepool paths unchanged
   - Keeps storage module (skips Key Vault resources)
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
3. **1 federated identity credential** (`azurerm_federated_identity_credential`) - Enables workload identity for storage access (replaces SAS token auth)

**Safe updates** (no infrastructure replacement):
1. **Storage account network rules** - `default_action` changes from `Allow` to `Deny` (more secure, subnets still allowed)
2. **Storage account TLS** - `min_tls_version` set to `TLS1_2` (was unset)
3. **Backend secret** - Updated `persist_backend_url` (SAS token removed, workload identity used instead)
4. **Operator helm release** - Helm values updated with new structure (node selectors, license key checks, etc.)

**Preserved** (no replacement):
- AKS cluster (network_plugin, network_policy, outbound_type all preserved)
- PostgreSQL Flexible Server (server name with random suffix preserved)
- VNet, subnets, DNS zone
- Storage account and container
- Node pools (system + materialize)
- Operator and cert-manager helm releases
- All Materialize instances and data

**STOP if you see these being destroyed:**
- AKS Cluster (`azurerm_kubernetes_cluster.aks`)
- PostgreSQL Server (`azurerm_postgresql_flexible_server.postgres`)
- Storage Account (`module.storage.azurerm_storage_account.materialize`)
- Materialize instances
- VNet or subnets

If critical infrastructure is being destroyed, verify your `terraform.tfvars` values match your existing infrastructure.

## Post-Migration: Optional Improvements

After migration is verified and stable, you can gradually adopt new module features:

- **Switch to new AKS module** — Adopts NAT gateway outbound and cilium networking (requires cluster recreation — plan maintenance window)
- **Switch to new networking module** — Uses Azure Verified Module (AVM) with NAT gateway
- **Switch to new database module** — Drops random suffix naming (requires DB migration)
- **Uncomment CoreDNS module** — Manage CoreDNS via Terraform (AKS manages it by default)
- **Add node taints** on the Materialize node pool for workload isolation
- **Add node selectors** to operator and cert-manager for scheduling control
- **Delete old Key Vault** — The old SAS token Key Vault is no longer needed (see Cleanup section)

## Troubleshooting

| Problem | Solution |
|---------|----------|
| State pull fails | Check Azure credentials (`az login`), backend config, run `terraform init` in old directory |
| "Only X resources" error (X < 10) | Old state not accessible — verify backend configuration |
| Provider version mismatch | Old module uses azurerm v3, new uses v4. Run `terraform init -upgrade` in new directory |
| AKS cluster being recreated | Verify `main.tf` has `network_plugin = "azure"`, `network_policy = "azure"`, no `outbound_type` |
| Database server being recreated | Verify `random_string.postgres_name_suffix` is in state (preserves `{prefix}-{random}-pg` naming) |
| Helm releases timing out | Remove from state: `terraform state rm 'module.operator.helm_release.materialize_operator'` etc. See [Helm Releases](#helm-releases-timing-out) |
| Storage "already exists" error | Import: `terraform import 'module.storage.azurerm_storage_account.materialize' '/subscriptions/.../storageAccounts/<name>'` |
| Materialize can't find data | Verify `old_db_password`, `database_name`, and `materialize_instance_name` in `terraform.tfvars` |
| TLS errors after migration | Verify `use_self_signed_cluster_issuer` matches old module setting |
| Plan shows Kubernetes version change | Set `kubernetes_version` in terraform.tfvars to match your cluster (null means "latest") |
| Plan shows environmentd version change | Set `environmentd_version` in terraform.tfvars to your current version tag |
| Node pool rotation in plan | Verify `tags` in terraform.tfvars includes `managed_by = "terraform"` and `module = "materialize"` (used as node labels) |
| Plan shows too many destroys | Review `terraform.tfvars` values, ensure they match existing infrastructure |

**If script fails with "No transformation rule":**
- Your setup has custom resources not in the standard module
- Add custom transformation rules to `auto-migrate.py` (see [Manual Migration](#manual-migration-for-custom-setups))

### Data Path Matching

The most critical part of migration is ensuring Materialize connects to the same data. These values must match exactly:

**metadata_backend_url** (PostgreSQL connection):
```
postgres://user:password@host/DATABASE_NAME?sslmode=require
```
- `user` = `database_username` variable (default: `materialize`)
- `password` = `old_db_password` variable (your existing database password)
- `DATABASE_NAME` = `database_name` variable (default: `materialize`)

**persist_backend_url** (Azure Blob Storage path):
```
https://<storage-account>.blob.core.windows.net/materialize
```
- The new format uses workload identity instead of SAS tokens
- The storage container name must be `materialize` (default)
- Materialize uses the same blob paths internally regardless of auth method

**external_login_password_mz_system** (login password):
- Must be your existing password, not a new random one
- Get from old config: look for `external_login_password_mz_system` in your old `terraform.tfvars`

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
kubectl get pods -n materialize-environment
# All should be Running or Completed

# 4. Test connectivity
terraform output load_balancer_details
# Use the balancerd_ip to connect:
psql -h <balancerd-ip> -p 6875 -U mz_system -d materialize
# Use: terraform output -raw external_login_password_mz_system

# 5. Verify storage
az storage container list --account-name $(terraform output -json storage | jq -r '.name') --auth-mode login
# Should show the "materialize" container

# 6. Check PostgreSQL
terraform output database
# Verify server name matches your existing server
```

**Success criteria:**
- Auto-migrate.py shows 0 failures
- Terraform plan shows only expected changes (additions for `kubectl_manifest`, federated identity credential)
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
  'module.networking.azurerm_virtual_network.vnet' \
  'azurerm_virtual_network.vnet'

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
- `module.aks.*` → root level (remove module prefix)
- `module.aks.azurerm_kubernetes_cluster_node_pool.materialize` → `azurerm_kubernetes_cluster_node_pool.system` (rename)
- `module.database.*` → root level (remove module prefix)
- `module.materialize_nodepool.*` → keep unchanged
- `module.storage.*` → keep unchanged (skip `azurerm_key_vault`)
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

**Manual cleanup - Old Key Vault:**

The old module created an Azure Key Vault for SAS token storage. This is no longer needed (workload identity replaces SAS tokens). The Key Vault is skipped during migration (not moved to new state), so it remains in Azure but is not managed by Terraform.

To delete it manually:
```bash
# Find the old key vault
az keyvault list --resource-group <your-resource-group> --query "[?contains(name, 'sas')].name" -o tsv

# Delete it (soft-delete)
az keyvault delete --name <key-vault-name> --resource-group <your-resource-group>

# Purge it (permanent delete)
az keyvault purge --name <key-vault-name>
```
