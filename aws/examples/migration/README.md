# Migration Guide: AWS Terraform Module

Migrate from the old `terraform-aws-materialize` module to the new `materialize-terraform-self-managed` modular approach.

> **Important:** This migration example is a **starting point**, not a turnkey solution. Every deployment is different — your VPC layout, node group sizing, instance types, database configuration, and custom modifications all affect the migration. **You are expected to review and adapt both `main.tf` and `auto-migrate.py` to match your specific infrastructure before running anything.** Always use `--dry-run` first, carefully inspect `terraform plan` output, and never apply changes you don't understand. The migration script modifies Terraform state, which is difficult to undo if done incorrectly.

## Quick Start

**Prerequisites:** Terraform CLI, Python 3.7+, AWS CLI, access to your old Terraform state

```bash
# CRITICAL: Verify old state access first
cd /path/to/old/terraform
terraform state pull | jq '.resources | length'
# Must show 100+ resources

# Setup
cp -r aws/examples/migration /path/to/new/terraform
cd /path/to/new/terraform
chmod +x auto-migrate.py

# Configure: copy and edit terraform.tfvars
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars to match your existing infrastructure:
#   - REQUIRED: name_prefix, license_key, environment, materialize_instance_name
#   - REQUIRED: old_db_password, external_login_password_mz_system
#   - INFRA: vpc_cidr, availability_zones, subnet CIDRs, cluster_version
#   - SIZING: node group instance types and min/max/desired sizes
#   - DATABASE: postgres_version, db_instance_class, storage settings

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
terraform output nlb_dns_name
```

**Expected Results:**
- **Dry-run**: ~120 resources total, ~110+ moved, ~6 skipped (data sources, cert-manager/NLB bindings due to provider type change), 0 failed
- **Terraform plan**: ~6 additions (cert-manager + NLB target bindings as `kubectl_manifest`), some IAM/EKS access updates
- **Preserved**: NLB, listeners, target groups, security group rules, EKS cluster, RDS database, VPC, S3 bucket, all Materialize instances

## Migration Checklist

Track your progress:

- [ ] **Prerequisites** - Verify Terraform version, state access, backup current state
- [ ] **Prepare** - Copy migration example, generate terraform.tfvars
- [ ] **Customize terraform.tfvars** - Set all required variables (see `terraform.tfvars.example`)
- [ ] **Review main.tf and auto-migrate.py** - Verify they match your infrastructure; adapt if you have custom modifications
- [ ] **Dry Run** - Test with `--dry-run`, review output carefully, verify 0 failures
- [ ] **Migrate State** - Run auto-migrate.py (handles state moves, IPv6 cleanup, SG imports)
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
# Should show 100+ resources
# If <10, your state isn't accessible
```

**Common issues:**
- **Remote backend not configured**: State is in S3/Terraform Cloud but no backend config in directory
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

See `terraform.tfvars.example` for the full list with inline documentation and `aws` CLI commands to discover each value.

**Required variables** (no defaults - must be set):

| Variable | Description | How to Find |
|----------|-------------|-------------|
| `name_prefix` | Prefix used for all resource names | Check your old `terraform.tfvars` or `main.tf` |
| `aws_profile` | AWS CLI profile for authentication | Your existing AWS profile name |
| `license_key` | Materialize license key | From your old config or Materialize team |
| `environment` | Environment name from old module (e.g., `production`) | Check your old module's `environment` variable |
| `materialize_instance_name` | Your Materialize instance name | `kubectl get materialize -A` |
| `old_db_password` | Existing RDS database password | From your old `terraform.tfvars`, Terraform Cloud, or secrets manager |
| `external_login_password_mz_system` | Existing mz_system user password | `terraform output -raw external_login_password_mz_system` (in old directory) |

**Infrastructure variables** (have defaults matching old module - verify they match yours):

| Variable | Default | How to Verify |
|----------|---------|---------------|
| `vpc_cidr` | `10.0.0.0/16` | `aws ec2 describe-vpcs` |
| `availability_zones` | `["us-east-1a", "us-east-1b", "us-east-1c"]` | Must match your region |
| `cluster_version` | `1.32` | `aws eks describe-cluster --name <prefix>-eks --query cluster.version` |
| `environmentd_image_ref` | `materialize/environmentd:v26.5.1` | `kubectl get materialize -A -o jsonpath='{.items[0].spec.environmentdImageRef}'` |
| `base_instance_types` | `["r7g.xlarge"]` | `aws eks describe-nodegroup --cluster-name <prefix>-eks --nodegroup-name <prefix>` |
| `mz_instance_types` | `["r7gd.2xlarge"]` | `aws eks describe-nodegroup --cluster-name <prefix>-eks --nodegroup-name <prefix>-mz-swap` |
| `postgres_version` | `17` | `aws rds describe-db-instances` |
| `db_instance_class` | `db.m6i.large` | `aws rds describe-db-instances` |

**Data-path critical variables** - getting these wrong means Materialize won't find its existing data:
- `old_db_password` - used in `metadata_backend_url` to connect to the correct RDS database
- `environment` - used in `persist_backend_url` to locate existing S3 data (format: `s3://bucket/{environment}-{instance}:...`)
- `materialize_instance_name` - used as the database name in `metadata_backend_url` and as part of the S3 path

## What Changed: Old vs New Module

| Aspect | Old Module | New Module | Migration Impact |
|--------|-----------|------------|------------------|
| **Structure** | Monolithic | Modular (networking, eks, database, storage, operator, nlb) | State paths change |
| **Module Names** | `certificates`, `materialize_node_group` | `cert_manager`, `mz_node_group` | Automated rename |
| **Operator Resources** | All in `module.operator[0].*` | Split: operator module + root-level instances | Moved blocks handle this |
| **NLB Naming** | Explicit: `${prefix}-${instance}` | name_prefix (generates unique) | Migration preserves via `nlb_name` param |
| **NLB Security Groups** | None | Optional SG per NLB | `create_security_group = false` during migration |
| **Provider** | `kubernetes_manifest` | `kubectl_manifest` (cert-manager + bindings) | Skipped in state mv, created fresh |
| **IAM Roles** | Root level | In `storage` module | State path changes |
| **Node Groups** | In EKS module | Separate `eks-node-group` module | Better modularity |
| **TLS Config** | In operator Helm values | Passed via `helm_values` variable | Configured in migration `main.tf` |
| **DB Password** | `random_password` resource | Explicit variable (`old_db_password`) | Must provide existing password |
| **S3 Persist Path** | `{env}-{instance}:serviceaccount:{ns}:{instance}` | Same format via `environment` variable | Must set `environment` variable |

Most changes are state path updates (no infrastructure changes). Resources with provider type changes (`kubernetes_manifest` to `kubectl_manifest`) are skipped during state migration and created fresh - `kubectl apply` adopts the existing Kubernetes resources with zero disruption.

## How Auto-Migration Works

The `auto-migrate.py` script:

1. **Validates state access** - Ensures old state has actual infrastructure (100+ resources)
2. **Analyzes structure** - Auto-detects if you wrapped the module (e.g., `module "mz" { ... }`)
3. **Applies transformation rules**:
   - Removes `[0]` indices: `module.operator[0].*` → `module.operator.*`
   - Renames modules: `module.certificates` → `module.cert_manager`
   - Moves operator resources: `module.operator.kubernetes_manifest.materialize_instances` → `kubernetes_manifest.materialize_instances`
   - Preserves helm releases: operator, AWS LBC, cert-manager
   - Skips data sources (automatically recreated)
   - Skips cert-manager and NLB target group bindings (provider type change; recreated safely)
4. **Validates migrated state** (read-only check for potential issues)
5. **Prepares resource imports**:
   - Discovers security group IDs from the migrated state
   - Strips IPv6 CIDR ranges from EKS node SG rules in AWS (IPv4 rules untouched)
   - Removes stale SG rule instances from local state (they have outdated attributes after state mv)
   - Queues database SG rules and EKS node SG rules for import
6. **Migrates resources** - Uses `terraform state mv` between local state files
7. **Pushes updated states** - Updates both old and new remote backends
8. **Imports resources** - Runs `terraform import` directly against remote backend for queued SG rules

**Work files** (in `.migration-work/`):
- `old-state-backup-TIMESTAMP.tfstate` - Original backup for emergency restore
- `old.tfstate`, `new.tfstate` - Working copies
- Never modifies original state files directly

## Expected Changes After Migration

**Additions** (new resources that adopt existing Kubernetes objects):
1. **3 cert-manager resources** (`kubectl_manifest`) - Adopts existing cert-manager K8s resources
2. **3 NLB target group bindings** (`kubectl_manifest`) - Adopts existing target group binding K8s resources

**Safe updates** (no infrastructure replacement):
1. **IAM policy attachments** - Terraform state quirk, no functional impact
2. **EKS access entries** - Configuration change, brief access resync

**Preserved** (no replacement):
- NLB (explicit naming via `nlb_name` parameter, no security group added)
- Listeners and target groups
- EKS node security group rules (IPv6 stripped, IPv4 preserved, imported fresh)
- Database security group rules (imported by script)
- EKS cluster, RDS database, VPC, NAT gateways
- S3 bucket and persist data
- All Materialize instances and helm releases

**STOP if you see these being destroyed:**
- NAT Gateways (unless intentionally reducing from 3 to 1)
- RDS Database
- Materialize instances (`kubernetes_manifest.materialize_instances`)
- EKS Cluster
- NLB (should show "has moved" instead)
- Node groups or launch templates

If critical infrastructure is being destroyed, verify your `terraform.tfvars` values match your existing infrastructure.

## Post-Migration: Optional Improvements

After migration is verified and stable, you can make these optional changes to `main.tf` and `terraform.tfvars`:

- Set `single_nat_gateway = true` to reduce costs (from 3 NAT gateways to 1)
- Set `create_security_group = true` in NLB module to add NLB security groups
- Remove the `nlb_name` override to adopt the new name_prefix-based naming
- Change node labels from `"system"` to `"base"`/`"generic"` and add dedicated generic nodes
- Uncomment the `coredns` module to manage CoreDNS via Terraform
- Uncomment `node_taints` on the Materialize node group
- Enable Karpenter for autoscaling (currently commented out in `main.tf`)

## Troubleshooting

| Problem | Solution |
|---------|----------|
| State pull fails | Check AWS credentials, backend config, run `terraform init` in old directory |
| "Only X resources" error (X < 10) | Old state not accessible - verify backend configuration |
| "ResourceInUseException" on EKS access entries | Import them: `terraform import 'module.eks.module.eks.aws_eks_access_entry.this["KEY"]' 'CLUSTER:PRINCIPAL_ARN'` (error message shows values) |
| "InvalidPermission.Duplicate" on security group rules | Script should handle this automatically. If it persists, see [Security Group Import Guide](#importing-security-group-rules) |
| Helm releases timing out | Remove from state: `terraform state rm 'module.operator.helm_release.materialize_operator'` etc. See [Helm Releases](#helm-releases-timing-out) |
| NAT gateways being destroyed | Set `single_nat_gateway = false` in `terraform.tfvars` |
| NLB being replaced | These are managed in `main.tf` - verify `nlb_name` and `create_security_group = false` |
| Launch template being replaced | These are managed in `main.tf` - verify `launch_template_name` matches old naming |
| Node group being replaced | These are managed in `main.tf` - verify `node_group_name` matches old naming |
| Materialize can't find data | Verify `environment`, `old_db_password`, and `materialize_instance_name` in `terraform.tfvars` |
| TLS errors after migration | Verify `use_self_signed_cluster_issuer` matches old module setting |
| Plan shows too many destroys | Review `terraform.tfvars` values, ensure they match existing infrastructure |

**If script fails with "No transformation rule":**
- Your setup has custom resources not in standard module
- Add custom transformation rules to `auto-migrate.py` (see [Manual Migration](#manual-migration-for-custom-setups))

### Data Path Matching

The most critical part of migration is ensuring Materialize connects to the same data. Three values must match exactly:

**metadata_backend_url** (RDS connection):
```
postgres://user:password@host/DATABASE_NAME?sslmode=require
```
- `DATABASE_NAME` = `coalesce(instance.database_name, instance.name)` from the old module
- If you didn't set `database_name` explicitly, it defaults to the instance name (e.g., `analytics`)
- Set via `database_name` field in `materialize_instances` local in `main.tf`

**persist_backend_url** (S3 path):
```
s3://bucket/ENVIRONMENT-INSTANCE:serviceaccount:NAMESPACE:INSTANCE
```
- `ENVIRONMENT` comes from the `environment` variable (e.g., `production`)
- This must match the old module's `environment` variable exactly
- Check your S3 bucket to verify: `aws s3 ls s3://your-bucket/ --recursive | head`

**external_login_password_mz_system** (login password):
- Must be your existing password, not a new random one
- Get from old config: `terraform output -raw external_login_password_mz_system`

### Importing Resources Not in Old State

Some resources may exist in AWS but weren't tracked in your old Terraform state. The migration script handles most of these automatically (database SG rules, EKS node SG rules). If you still encounter issues:

#### Importing EKS Access Entries

If `terraform apply` fails with:
```
Error: creating EKS Access Entry (cluster-name:arn:...): ResourceInUseException
```

**Extract the import command from the error:**
- Resource path: `module.eks.module.eks.aws_eks_access_entry.this["KEY"]`
- Import ID format: `CLUSTER_NAME:PRINCIPAL_ARN` (both shown in error message)

**Example:**
```bash
terraform import \
  'module.eks.module.eks.aws_eks_access_entry.this["cluster_creator"]' \
  'your-prefix-eks:arn:aws:iam::123456789012:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_Administrator_abc123'
```

**After importing, run `terraform apply` again.**

#### Importing Security Group Rules

The migration script automatically imports database and EKS node SG rules. If you still see errors:

```
Error: ... InvalidPermission.Duplicate: the specified rule "..." already exists
```

**Build the import command:**

1. Get security group ID from error (e.g., `sg-070853f83fabc8fde`)
2. Get rule details from error (e.g., `peer: sg-xxx, TCP, from port: 5432, to port: 5432`)
3. Format: `SGID_DIRECTION_PROTOCOL_FROMPORT_TOPORT_SOURCE`

**Example for ingress rule:**
```bash
# Database security group rule: EKS nodes -> RDS port 5432
terraform import \
  'module.database.aws_security_group_rule.eks_nodes_postgres_ingress' \
  'sg-070853f83fabc8fde_ingress_tcp_5432_5432_sg-04039a9ba7633fdda'
```

**Example for egress rule:**
```bash
# Database security group rule: allow all egress
terraform import \
  'module.database.aws_security_group_rule.allow_all_egress' \
  'sg-070853f83fabc8fde_egress_-1_0_0_0.0.0.0/0'
```

**After importing all rules, run `terraform apply` again.**

#### Helm Releases Timing Out

If helm releases (metrics_server, materialize_operator, aws_load_balancer_controller, cert_manager) timeout during `terraform apply`, it means:
- They're already installed and working in your cluster
- Terraform is trying to update them (which is unnecessary)
- The update is slow or stuck, causing timeout

**Quick fix - Remove from Terraform state:**
```bash
# These helm releases will continue running, but Terraform stops managing them
terraform state rm 'module.operator.helm_release.metrics_server[0]'
terraform state rm 'module.operator.helm_release.materialize_operator'
terraform state rm 'module.aws_lbc.helm_release.aws_load_balancer_controller'
terraform state rm 'module.cert_manager.helm_release.cert_manager[0]'

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
# Should show ~120+ resources

# 2. Verify Materialize instances
kubectl get materialize -A
# Should show STATUS: running

# 3. Check pods
kubectl get pods -n materialize-environment
# All should be Running or Completed

# 4. Test connectivity
terraform output nlb_dns_name
psql -h <nlb-dns> -p 6875 -U mz_system -d materialize
# Should connect and allow queries
# Use: terraform output -raw external_login_password_mz_system

# 5. Verify S3 bucket
aws s3 ls s3://$(terraform output -raw s3_bucket_name)/
# Should show persist data under {environment}-{instance}:serviceaccount:... prefix

# 6. Check RDS
aws rds describe-db-instances --db-instance-identifier $(terraform output -raw database_endpoint | cut -d: -f1)
# Should show available status
```

**Success criteria:**
- Auto-migrate.py shows 0 failures
- Terraform plan shows only expected changes (additions for kubectl_manifest, minor updates)
- Terraform apply succeeds
- `kubectl get materialize -A` shows STATUS: running
- Can connect via psql to NLB endpoint
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

**When to use manual migration:**
- Split old module into multiple instances
- Added substantial custom infrastructure
- Nested module multiple levels deep
- One-off customizations that don't benefit from scripting

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
  'module.operator[0].helm_release.materialize_operator' \
  'module.operator.helm_release.materialize_operator'

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
- Remove `[0]` indices from module paths
- `module.certificates.*` → `module.cert_manager.*`
- `module.materialize_node_group.*` → `module.mz_node_group.*`
- `module.operator.kubernetes_manifest.materialize_instances[X]` → `kubernetes_manifest.materialize_instances[X]`
- `module.operator.kubernetes_namespace.instance_namespaces[X]` → `kubernetes_namespace.instance_namespaces[X]`
- `module.operator.kubernetes_secret.materialize_backends[X]` → `kubernetes_secret.materialize_backends[X]`
- Skip all data sources (recreated automatically)
- Skip cert-manager `kubernetes_manifest` resources (recreated as `kubectl_manifest`)
- Skip NLB target group binding `kubernetes_manifest` resources (recreated as `kubectl_manifest`)

## Cleanup

**After verifying everything works:**

```bash
# Remove migration work directory
rm -rf .migration-work/

# (Optional) Clean up old Terraform directory
cd /path/to/old/terraform
rm -rf .terraform terraform.tfstate*

# (Optional) Delete RDS backup snapshot if created
aws rds delete-db-snapshot --db-snapshot-identifier migration-backup-YYYYMMDD
```
