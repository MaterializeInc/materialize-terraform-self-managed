# Migration Guide: AWS Terraform Module

Migrate from the old `terraform-aws-materialize` module to the new `materialize-terraform-self-managed` modular approach.

## Quick Start

**Prerequisites:** Terraform CLI, Python 3.7+, access to your old Terraform state

```bash
# CRITICAL: Verify old state access first
cd /path/to/old/terraform
terraform state pull | jq '.resources | length'
# Must show 100+ resources

# Setup
cp -r aws/examples/migration /path/to/new/terraform
cd /path/to/new/terraform
chmod +x auto-migrate.py

# Generate config from old setup
./auto-migrate.py /path/to/old/terraform . --generate-tfvars
# Edit terraform.tfvars - add license_key, review detected values and customize as needed to match your existing infrastructure

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
- **Dry-run**: ~120 resources total, ~117 moved, ~3 skipped (data sources), 0 failed
- **Terraform plan**: Mostly safe recreations (cert-manager resources, target group bindings, IAM policy attachments, EKS access entries)
- **Preserved**: NLB, listeners, target groups, security group rules, EKS cluster, RDS database, VPC, all Materialize instances

## Migration Checklist

Track your progress:

- [ ] **Prerequisites** - Verify Terraform version, state access, backup current state
- [ ] **Prepare** - Copy migration example, generate terraform.tfvars
- [ ] **Customize** - Update main.tf to match your infrastructure (search for `# MIGRATION:`)
- [ ] **Dry Run** - Test with `--dry-run`, verify 0 failures
- [ ] **Migrate State** - Run auto-migrate.py
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

## What Changed: Old vs New Module

| Aspect | Old Module | New Module | Migration Impact |
|--------|-----------|------------|------------------|
| **Structure** | Monolithic | Modular (networking, eks, database, storage, operator, nlb) | State paths change |
| **Module Names** | `certificates`, `materialize_node_group` | `cert_manager`, `mz_node_group` | Automated rename |
| **Operator Resources** | All in `module.operator[0].*` | Split: operator module + root-level instances | Moved blocks handle this |
| **NLB Naming** | Explicit: `${prefix}-${instance}` | name_prefix (generates unique) | Migration preserves via `nlb_name` param |
| **Provider** | `kubernetes_manifest` | `kubectl_manifest` (cert-manager + bindings) | 6 resources recreated |
| **IAM Roles** | Root level | In `storage` module | State path changes |
| **Node Groups** | In EKS module | Separate `eks-node-group` module | Better modularity |

Most changes are state path updates (no infrastructure changes). Only 6 resources recreated due to provider change, which is safe.

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
4. **Cleans problematic resources**:
   - Removes EKS access entries (recreated to avoid conflicts)
   - Removes database security group rules (often already exist in AWS)
5. **Migrates resources** - Uses `terraform state mv` between state files
6. **Pushes updated states** - Updates both old and new backends

**Work files** (in `.migration-work/`):
- `old-state-backup-TIMESTAMP.tfstate` - Original backup for emergency restore
- `old.tfstate`, `new.tfstate` - Working copies
- Never modifies original state files directly

## Expected Changes After Migration

**Safe recreations** (unavoidable due to provider/module changes):
1. **3 cert-manager resources** - Provider change: `kubernetes_manifest` → `kubectl_manifest`
2. **3 NLB target group bindings** - Same provider change, brief reconnection during apply
3. **5 IAM policy attachments** - Terraform state quirk, no functional impact
4. **2 EKS access entries** - Configuration change, brief access resync
5. **3 database security group rules** - Weren't in old state, creating new ones

**Preserved** (no replacement):
- NLB (explicit naming via `nlb_name` parameter)
- Listeners and target groups (via NLB preservation)
- Security group rules with IPv6 (via `materialize_node_ingress_ipv6_cidrs`)
- EKS cluster, RDS database, VPC, NAT gateways
- All Materialize instances and helm releases

**STOP if you see these being destroyed:**
- NAT Gateways (unless intentionally reducing from 3 to 1)
- RDS Database
- Materialize instances (`kubernetes_manifest.materialize_instances`)
- EKS Cluster
- NLB (should show "has moved" instead)

If critical infrastructure is being destroyed, check [Customizing main.tf](#customizing-maintf-for-your-infrastructure).

## Customizing main.tf for Your Infrastructure

Before running terraform apply, update `main.tf` to match your existing setup. Search for `# MIGRATION:` comments.

**Key customizations:**
```hcl
# Line 34-35: Match your existing prefix
variable "name_prefix" {
  default = "your-prefix"  # CHANGE THIS
}

# Line 47-48: Match your instance name
locals {
  materialize_instance_name = "analytics"  # CHANGE THIS
}

# Line 98: Preserve 3 NAT gateways (prevents replacement)
single_nat_gateway = false

# Line 120: Match your EKS version
cluster_version = "1.32"

# Line 128: Preserve IPv6 rules (or set to [] to remove)
materialize_node_ingress_ipv6_cidrs = ["::/0"]

# Line 150-154: Match base node group settings
instance_types = ["t4g.medium"]
min_size       = 2
max_size       = 3
desired_size   = 2

# Line 185-189: Match Materialize node group settings
node_group_name = "${var.name_prefix}-mz-swap"
instance_types  = ["r7gd.2xlarge"]
min_size        = 1
max_size        = 10
desired_size    = 1

# Line 684: Preserve existing NLB name
nlb_name = "${var.name_prefix}-${each.key}"
```

**After successful migration**, you can optionally:
- Remove `nlb_name` to adopt name_prefix-based naming
- Set `materialize_node_ingress_ipv6_cidrs = []` to remove IPv6
- Set `single_nat_gateway = true` for cost savings
- Enable Karpenter for autoscaling (currently commented out)

## Troubleshooting

| Problem | Solution |
|---------|----------|
| State pull fails | Check AWS credentials, backend config, run `terraform init` in old directory |
| "Only X resources" error (X < 10) | Old state not accessible - verify backend configuration |
| "ResourceInUseException" on EKS access entries | **These weren't in your old state but exist in AWS.** Import them: `terraform import 'module.eks.module.eks.aws_eks_access_entry.this["KEY"]' 'CLUSTER:PRINCIPAL_ARN'` (error message shows exact KEY, CLUSTER, and PRINCIPAL_ARN to use) |
| "InvalidPermission.Duplicate" on security group rules | **These weren't in your old state but exist in AWS.** Import them: `terraform import 'RESOURCE_PATH' 'RULE_ID'` (see [Security Group Import Guide](#importing-security-group-rules) below) |
| Helm releases timing out during apply | **They're already installed and working.** Remove from state to stop Terraform managing them: `terraform state rm 'module.operator.helm_release.metrics_server[0]'` `terraform state rm 'module.operator.helm_release.materialize_operator'` `terraform state rm 'module.aws_lbc.helm_release.aws_load_balancer_controller'` `terraform state rm 'module.cert_manager.helm_release.cert_manager[0]'` - Then re-run `terraform apply` |
| NAT gateways being destroyed | Set `single_nat_gateway = false` in main.tf line 98 |
| NLB being replaced | Already fixed via `nlb_name` parameter in main.tf line 684 |
| Materialize instances being created | Uncommented in latest main.tf - they should be migrated, not created |
| Plan shows too many destroys | Review `# MIGRATION:` comments in main.tf, ensure settings match existing infrastructure |

**If script fails with "No transformation rule":**
- Your setup has custom resources not in standard module
- Add custom transformation rules to `auto-migrate.py` (see [Manual Migration](#manual-migration-for-custom-setups))

### Importing Resources Not in Old State

Some resources may exist in AWS but weren't tracked in your old Terraform state (created manually or by AWS). You need to import them manually.

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
# Error shows: your-prefix-eks:arn:aws:iam::400121260767:role/.../Administrator_...
# And resource: module.eks.module.eks.aws_eks_access_entry.this["cluster_creator"]

terraform import \
  'module.eks.module.eks.aws_eks_access_entry.this["cluster_creator"]' \
  'your-prefix-eks:arn:aws:iam::400121260767:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_Administrator_8f776055d1b2f7d4'
```

**After importing, run `terraform apply` again.**

#### Importing Security Group Rules

If `terraform apply` fails with:
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
  'sg-070853f83fabc8fde_egress_all_0_0_0.0.0.0/0'
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

**Alternative - Increase timeout:**
If you want Terraform to keep managing them, set longer timeout in provider config:
```hcl
# In main.tf, add to helm provider
provider "helm" {
  kubernetes {
    # ... existing config
  }

  # Increase timeout for slow helm operations
  timeout = 600  # 10 minutes instead of default 5
}
```

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
terraform output -raw external_login_password_mz_system
psql -h <nlb-dns> -p 6875 -U mz_system -d materialize
# Should connect and allow queries

# 5. Verify S3 bucket
aws s3 ls s3://$(terraform output -raw s3_bucket_name)/
# Should show persist data

# 6. Check RDS
aws rds describe-db-instances --db-instance-identifier $(terraform output -raw database_endpoint | cut -d: -f1)
# Should show available status
```

**Success criteria:**
- Auto-migrate.py shows 0 failures
- Terraform plan shows only expected changes
- Terraform apply succeeds
- `kubectl get materialize -A` shows STATUS: running
- Can connect via psql to NLB endpoint
- Test queries return expected data

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
- `⚠️ No transformation rule` - Add rules for these
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
