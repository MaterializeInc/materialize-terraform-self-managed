#!/usr/bin/env python3
"""
Automated Terraform State Migration Tool

Intelligently migrates resources from old to new Terraform state by:
1. Analyzing the old state file
2. Applying transformation rules
3. Moving resources to the new state

Usage:
    ./auto-migrate.py /path/to/old/terraform /path/to/new/terraform [--dry-run]
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Optional, List, Tuple


@dataclass
class MigrationRule:
    """A rule for transforming old resource paths to new paths"""
    pattern: str
    transform: callable
    description: str


class StateMigrator:
    def __init__(self, old_dir: Path, new_dir: Path, dry_run: bool = False):
        self.old_dir = old_dir
        self.new_dir = new_dir
        self.dry_run = dry_run
        self.work_dir = None
        self.module_prefix = None
        self.stats = {
            'total': 0,
            'moved': 0,
            'skipped': 0,
            'failed': 0,
        }

        # Define transformation rules
        self.rules = self._build_rules()

    def _build_rules(self) -> List[MigrationRule]:
        """
        Build transformation rules for resource path mapping.

        Rules are evaluated in order. The first matching rule wins.
        Add custom rules at the beginning of the list for specific cases.

        Example custom rule:
            MigrationRule(
                pattern=r'^module\.custom_module\.(.+)$',
                transform=lambda m: f'module.new_name.{m.group(1)}',
                description="Rename custom_module to new_name"
            ),
        """
        return [
            # Remove [0] index from various modules
            MigrationRule(
                pattern=r'^(module\.operator)\[0\]\.(.+)$',
                transform=lambda m: f"{m.group(1)}.{m.group(2)}",
                description="Remove [0] index from operator module"
            ),

            MigrationRule(
                pattern=r'^(module\.aws_lbc)\[0\]\.(.+)$',
                transform=lambda m: f"{m.group(1)}.{m.group(2)}",
                description="Remove [0] index from aws_lbc module"
            ),

            # Rename certificates module to cert_manager
            MigrationRule(
                pattern=r'^module\.certificates\.(.+)$',
                transform=lambda m: f'module.cert_manager.{m.group(1)}',
                description="Rename certificates module to cert_manager"
            ),

            # Skip self-signed cert-manager resources (kubernetes_manifest → kubectl_manifest type change)
            # The old module uses kubernetes_manifest, new uses kubectl_manifest in a different module.
            # Cross-type state mv is unreliable, so we skip these and let kubectl_manifest create
            # via kubectl apply, which adopts the existing K8s resources with zero disruption.
            MigrationRule(
                pattern=r'^module\.cert_manager\.kubernetes_manifest\.(self_signed_cluster_issuer|self_signed_root_ca_certificate|root_ca_cluster_issuer)\[0\]$',
                transform=lambda m: None,
                description="Skip self-signed cert resources (type change kubernetes_manifest→kubectl_manifest)"
            ),

            # Move root-level IAM roles to storage module
            MigrationRule(
                pattern=r'^aws_iam_role\.materialize_s3$',
                transform=lambda m: 'module.storage.aws_iam_role.materialize_s3',
                description="Move IAM role to storage module"
            ),

            MigrationRule(
                pattern=r'^aws_iam_role_policy\.materialize_s3$',
                transform=lambda m: 'module.storage.aws_iam_role_policy.materialize_s3',
                description="Move IAM role policy to storage module"
            ),

            # Rename node group modules
            MigrationRule(
                pattern=r'^module\.materialize_node_group\.(.+)$',
                transform=lambda m: f'module.mz_node_group.{m.group(1)}',
                description="Rename materialize_node_group to mz_node_group"
            ),

            # Migrate EKS internal managed node group to base_node_group
            # Old: module.eks.module.eks.module.eks_managed_node_group["{your-prefix}-system"].*
            # New: module.base_node_group.module.node_group.*
            MigrationRule(
                pattern=r'^module\.eks\.module\.eks\.module\.eks_managed_node_group\[.+?\]\.(.+)$',
                transform=lambda m: f'module.base_node_group.module.node_group.{m.group(1)}',
                description="Migrate EKS internal managed node group to base_node_group"
            ),

            # Move Materialize instance resources from operator module to root level
            # Old: module.operator.kubernetes_manifest.materialize_instances[...]
            # New: kubernetes_manifest.materialize_instances[...]
            MigrationRule(
                pattern=r'^module\.operator\.kubernetes_manifest\.materialize_instances(\[.+?\])$',
                transform=lambda m: f'kubernetes_manifest.materialize_instances{m.group(1)}',
                description="Move Materialize instance manifests from operator to root"
            ),

            # Move Materialize instance data sources from operator module to root level
            # Old: module.operator.data.kubernetes_resource.materialize_instances[...]
            # New: data.kubernetes_resource.materialize_instances[...]
            MigrationRule(
                pattern=r'^module\.operator\.data\.kubernetes_resource\.materialize_instances(\[.+?\])$',
                transform=lambda m: f'data.kubernetes_resource.materialize_instances{m.group(1)}',
                description="Move Materialize instance data sources from operator to root"
            ),

            # Move instance namespaces from operator module to root level
            # Old: module.operator.kubernetes_namespace.instance_namespaces[...]
            # New: kubernetes_namespace.instance_namespaces[...]
            MigrationRule(
                pattern=r'^module\.operator\.kubernetes_namespace\.instance_namespaces(\[.+?\])$',
                transform=lambda m: f'kubernetes_namespace.instance_namespaces{m.group(1)}',
                description="Move instance namespaces from operator to root"
            ),

            # Move backend secrets from operator module to root level
            # Old: module.operator.kubernetes_secret.materialize_backends[...]
            # New: kubernetes_secret.materialize_backends[...]
            MigrationRule(
                pattern=r'^module\.operator\.kubernetes_secret\.materialize_backends(\[.+?\])$',
                transform=lambda m: f'kubernetes_secret.materialize_backends{m.group(1)}',
                description="Move backend secrets from operator to root"
            ),

            # Move db init jobs from operator module to root level
            # Old: module.operator.kubernetes_job.db_init_job[...]
            # New: kubernetes_job.db_init_job[...]
            MigrationRule(
                pattern=r'^module\.operator\.kubernetes_job\.db_init_job(\[.+?\])$',
                transform=lambda m: f'kubernetes_job.db_init_job{m.group(1)}',
                description="Move db init jobs from operator to root"
            ),

            # Skip NLB TargetGroupBinding resources (kubernetes_manifest → kubectl_manifest type change)
            # The old module uses kubernetes_manifest, new uses kubectl_manifest.
            # Skipping lets kubectl_manifest create via kubectl apply, which adopts the existing
            # K8s resource with zero disruption (no delete + recreate).
            MigrationRule(
                pattern=r'^module\.nlb\[.+?\]\.module\.target_.+\.kubernetes_manifest\.target_group_binding$',
                transform=lambda m: None,
                description="Skip NLB target group binding (type change kubernetes_manifest→kubectl_manifest)"
            ),

            # Keep NLB resources (handles both indexed and nested submodules)
            MigrationRule(
                pattern=r'^(module\.nlb\[.+)$',
                transform=lambda m: m.group(1),
                description="Keep NLB module path unchanged"
            ),

            # Keep operator module helm releases unchanged
            MigrationRule(
                pattern=r'^(module\.operator\.helm_release\..+)$',
                transform=lambda m: m.group(1),
                description="Keep operator helm releases unchanged"
            ),

            # Keep aws_lbc module helm release unchanged
            MigrationRule(
                pattern=r'^(module\.aws_lbc\.helm_release\..+)$',
                transform=lambda m: m.group(1),
                description="Keep AWS LBC helm release unchanged"
            ),

            # Keep cert_manager module helm release unchanged
            MigrationRule(
                pattern=r'^(module\.cert_manager\.helm_release\..+)$',
                transform=lambda m: m.group(1),
                description="Keep cert-manager helm release unchanged"
            ),

            # Default: keep same path (for networking, eks, database, storage, operator, aws_lbc, cert_manager)
            MigrationRule(
                pattern=r'^(module\.(networking|eks|database|storage|operator|aws_lbc|cert_manager)\..+)$',
                transform=lambda m: m.group(1),
                description="Keep module path unchanged"
            ),

            # Skip data sources - they will be recreated automatically
            # Matches both top-level (data.*) and nested (module.*.data.*)
            MigrationRule(
                pattern=r'^(.*\.)?data\..*$',
                transform=lambda m: None,  # None means skip
                description="Skip data source (will be recreated)"
            ),

            # Skip other resources that don't map (like old cloudwatch log groups)
            MigrationRule(
                pattern=r'^aws_cloudwatch_log_group\.materialize\[.*\]$',
                transform=lambda m: None,  # Skip - new module structure may differ
                description="Skip old cloudwatch log group"
            ),
        ]

    def log(self, message: str, level: str = 'INFO'):
        """Log a message with timestamp"""
        timestamp = datetime.now().strftime('%H:%M:%S')
        prefix = {'INFO': '  ', 'WARN': '⚠️ ', 'ERROR': '❌', 'SUCCESS': '✅'}
        print(f"[{timestamp}] {prefix.get(level, '  ')}{message}")

    def log_section(self, title: str):
        """Log a section header"""
        print(f"\n{'='*60}")
        print(f"  {title}")
        print('='*60)

    def run_terraform(self, args: List[str], cwd: Path, capture: bool = True) -> subprocess.CompletedProcess:
        """Run terraform command"""
        cmd = ['terraform'] + args
        return subprocess.run(
            cmd,
            cwd=cwd,
            capture_output=capture,
            text=True,
            check=False
        )

    def detect_module_prefix(self, resources: List[str]) -> Optional[str]:
        """Auto-detect if resources are wrapped in a parent module"""
        # Look for pattern like: module.wrapper.module.networking...
        # But exclude internal nesting like module.eks.module.eks (where names match)
        pattern = re.compile(r'^module\.([^.]+)\.module\.(networking|eks|database)')

        for resource in resources:
            match = pattern.match(resource)
            if match:
                prefix_name = match.group(1)  # e.g., "materialize_infrastructure" or "eks"
                module_name = match.group(2)  # e.g., "networking", "eks", "database"

                # Skip if prefix matches module name - this is internal nesting, not a wrapper
                # Example: module.eks.module.eks.* is internal, not wrapped
                if prefix_name == module_name:
                    continue

                # Found a real wrapper
                return f"module.{prefix_name}"

        return None

    def strip_prefix(self, path: str) -> str:
        """Remove module prefix if present"""
        if self.module_prefix and path.startswith(f"{self.module_prefix}."):
            return path[len(self.module_prefix) + 1:]
        return path

    def transform_path(self, old_path: str) -> Tuple[Optional[str], Optional[str]]:
        """
        Transform old path to new path using rules.
        Returns (new_path, rule_description) or (None, None) if no rule matches.
        """
        # Strip module prefix first
        path_to_transform = self.strip_prefix(old_path)

        # Try each rule
        for rule in self.rules:
            match = re.match(rule.pattern, path_to_transform)
            if match:
                new_path = rule.transform(match)
                return new_path, rule.description

        # No rule matched
        return None, None

    def get_resources(self, state_file: Path) -> List[str]:
        """Get list of resources from state file by parsing JSON directly"""
        try:
            # Check if file is empty or doesn't exist
            if not state_file.exists() or state_file.stat().st_size == 0:
                return []

            with open(state_file, 'r') as f:
                state = json.load(f)

            resources = []
            for resource in state.get('resources', []):
                resource_type = resource.get('type', '')
                resource_name = resource.get('name', '')
                resource_mode = resource.get('mode', 'managed')

                # Build resource address
                # Handle module path
                module_path = resource.get('module', '')
                if module_path:
                    # For resources in modules, add data. prefix if it's a data source
                    if resource_mode == 'data':
                        full_path = f"{module_path}.data.{resource_type}.{resource_name}"
                    else:
                        full_path = f"{module_path}.{resource_type}.{resource_name}"
                else:
                    # Top-level resources
                    if resource_mode == 'data':
                        full_path = f"data.{resource_type}.{resource_name}"
                    else:
                        full_path = f"{resource_type}.{resource_name}"

                # Handle each instance (for resources with count/for_each)
                instances = resource.get('instances', [])
                if not instances:
                    resources.append(full_path)
                else:
                    for instance in instances:
                        index_key = instance.get('index_key')
                        if index_key is not None:
                            if isinstance(index_key, int):
                                resources.append(f"{full_path}[{index_key}]")
                            else:
                                # String key (for_each)
                                resources.append(f'{full_path}["{index_key}"]')
                        else:
                            resources.append(full_path)

            return resources
        except Exception as e:
            # Only log errors for non-empty files (unexpected errors)
            if state_file.exists() and state_file.stat().st_size > 0:
                self.log(f"Error reading state file {state_file}: {e}", 'ERROR')
            return []

    def resource_exists_in_new(self, resource: str) -> bool:
        """Check if resource already exists in new state"""
        new_state = self.work_dir / 'new.tfstate'
        # Suppress errors for empty state file (expected on first migration)
        try:
            resources = self.get_resources(new_state)
            return resource in resources
        except:
            return False

    def move_resource(self, old_path: str, new_path: str) -> bool:
        """Move resource from old state to new state"""
        if self.dry_run:
            return True

        # Use relative paths from new_dir, not from work_dir
        old_state_rel = os.path.relpath(self.work_dir / "old.tfstate", self.new_dir)
        new_state_rel = os.path.relpath(self.work_dir / "new.tfstate", self.new_dir)

        result = self.run_terraform(
            [
                'state', 'mv',
                f'-state={old_state_rel}',
                f'-state-out={new_state_rel}',
                old_path,
                new_path
            ],
            cwd=self.new_dir,  # Run from new_dir where terraform is configured
            capture=True
        )

        return result.returncode == 0

    def normalize_instance_namespace_keys(self):
        """
        Normalize instance_namespaces keys from namespace names to instance names.

        The old operator module used namespace names as keys for instance_namespaces,
        but instance names for other resources. This normalizes to use instance names consistently.
        """
        try:
            # Load new state to analyze
            state = json.loads((self.work_dir / 'new.tfstate').read_text())

            # Build mapping: namespace_name -> instance_name
            # by looking at kubernetes_manifest.materialize_instances resources
            namespace_to_instance = {}

            for resource in state.get('resources', []):
                # Look for materialize_instances manifests in operator module
                if (resource.get('module') == 'module.operator' and
                    resource['type'] == 'kubernetes_manifest' and
                    resource['name'] == 'materialize_instances'):

                    for instance in resource.get('instances', []):
                        if 'index_key' in instance and 'attributes' in instance:
                            instance_name = instance['index_key']
                            manifest_attr = instance['attributes'].get('manifest', {})

                            # Extract manifest - it may be stored as a value dict
                            if 'value' in manifest_attr:
                                manifest = manifest_attr['value']
                            else:
                                manifest = manifest_attr

                            namespace_name = manifest.get('metadata', {}).get('namespace')

                            if namespace_name:
                                namespace_to_instance[namespace_name] = instance_name
                                self.log(f"Detected mapping: namespace '{namespace_name}' -> instance '{instance_name}'")

            if not namespace_to_instance:
                self.log("No namespace-to-instance mappings found (may already be normalized)")
                return

            # Track if we modify the state
            state_modified = False

            # Find instance_namespaces resources that need key normalization
            for resource in state.get('resources', []):
                if (resource.get('module') == 'module.operator' and
                    resource['type'] == 'kubernetes_namespace' and
                    resource['name'] == 'instance_namespaces'):

                    # Check for existing keys
                    existing_keys = {inst.get('index_key') for inst in resource.get('instances', [])}

                    # Process instances, removing those that need normalization
                    instances_to_keep = []

                    for instance in resource.get('instances', []):
                        if 'index_key' in instance:
                            current_key = instance['index_key']

                            # Check if this key is a namespace name that needs normalization
                            if current_key in namespace_to_instance:
                                instance_name = namespace_to_instance[current_key]

                                if current_key != instance_name:
                                    old_addr = f'module.operator.kubernetes_namespace.instance_namespaces[{json.dumps(current_key)}]'
                                    new_addr = f'module.operator.kubernetes_namespace.instance_namespaces[{json.dumps(instance_name)}]'

                                    self.log(f"→ Normalizing namespace key:")
                                    self.log(f"  {old_addr}")
                                    self.log(f"  ↳ {new_addr}")

                                    if not self.dry_run:
                                        # Check if target key already exists
                                        if instance_name in existing_keys and instance_name != current_key:
                                            # Target already exists, skip this instance (will be removed)
                                            self.log(f"  ⊘ Skipped (target key already exists)")
                                            continue
                                        else:
                                            # Modify the key
                                            instance['index_key'] = instance_name
                                            self.log(f"  ✓ Normalized")
                                            state_modified = True

                        instances_to_keep.append(instance)

                    # Update resource instances if we modified anything
                    if not self.dry_run and len(instances_to_keep) != len(resource.get('instances', [])):
                        resource['instances'] = instances_to_keep
                        state_modified = True

            # Save modified state if changes were made
            if state_modified and not self.dry_run:
                self.log("Saving normalized state...")
                # Increment serial when modifying state
                state['serial'] += 1
                (self.work_dir / 'new.tfstate').write_text(json.dumps(state, indent=2))
                self.log("✓ State saved")

        except Exception as e:
            self.log(f"Error during key normalization: {e}", 'WARN')
            self.log("This is non-fatal - you may need to manually normalize keys")

    def validate_migrated_state(self):
        """
        Validate migrated resources in new state.

        Only inspects resources that we moved - never touches anything else.
        Reports issues but does NOT delete anything from state.
        """
        try:
            state = json.loads((self.work_dir / 'new.tfstate').read_text())
            issues = []

            for resource in state.get('resources', []):
                resource_path = f"{resource.get('module', '')}.{resource['type']}.{resource['name']}" if resource.get('module') else f"{resource['type']}.{resource['name']}"

                for instance in resource.get('instances', []):
                    attrs = instance.get('attributes', {})
                    index_key = instance.get('index_key')
                    full_path = f"{resource_path}[{json.dumps(index_key)}]" if index_key else resource_path

                    # Check for null attributes on resources we migrated
                    # This can happen when terraform state mv crosses module boundaries
                    if not attrs or attrs.get('id') is None:
                        issues.append(full_path)
                        self.log(f"⚠ Resource may have null attributes after state mv: {full_path}")
                        self.log(f"  This can happen when moving resources across module boundaries.")
                        self.log(f"  If terraform apply fails for this resource, import it manually:")
                        self.log(f"    terraform import '{full_path}' '<resource-id>'")

            if issues:
                self.log(f"\nFound {len(issues)} resource(s) that may need attention after apply.")
                self.log(f"These were NOT removed from state - review terraform apply output.")
            else:
                self.log("✓ All migrated resources look valid")

        except Exception as e:
            self.log(f"Error during state validation: {e}", 'WARN')

    def prepare_imports(self) -> List[dict]:
        """
        Prepare resources for import: discover SG IDs, strip IPv6 from AWS,
        and return a list of imports to execute AFTER state push.

        This method runs BEFORE state push so it can read the local state files
        to discover SG IDs. AWS API calls (IPv6 stripping) happen here too.

        Returns a list of dicts: [{'addr': ..., 'import_id': ..., 'desc': ...}, ...]
        """
        imports_to_run = []

        try:
            new_state = json.loads((self.work_dir / 'new.tfstate').read_text())
        except Exception as e:
            self.log(f"Error reading state files: {e}", 'WARN')
            return imports_to_run

        # --- Discover Security Group IDs from state ---
        db_sg_id = None
        cluster_sg_id = None
        node_sg_id = None

        for resource in new_state.get('resources', []):
            module = resource.get('module', '')

            # Find DB security group from the database module
            if ('database' in module and resource['type'] == 'aws_db_instance'
                    and resource['name'] == 'this'):
                for inst in resource.get('instances', []):
                    vpc_sgs = inst.get('attributes', {}).get('vpc_security_group_ids', [])
                    if vpc_sgs:
                        db_sg_id = vpc_sgs[0]

            # Find module-created cluster SG from EKS (aws_security_group.cluster[0])
            # This is the SG used by the database module for ingress rules.
            # NOT the EKS-managed primary SG from vpc_config.cluster_security_group_id.
            if (module == 'module.eks.module.eks' and resource['type'] == 'aws_security_group'
                    and resource['name'] == 'cluster'):
                for inst in resource.get('instances', []):
                    cluster_sg_id = inst.get('attributes', {}).get('id')

            # Find node SG from EKS
            if (module == 'module.eks.module.eks' and resource['type'] == 'aws_security_group'
                    and resource['name'] == 'node'):
                for inst in resource.get('instances', []):
                    node_sg_id = inst.get('attributes', {}).get('id')

        # --- Database Security Group Rules ---
        # The old module used inline SG rules on the DB security group.
        # The new module uses standalone aws_security_group_rule resources.
        # These rules exist in AWS but NOT as separate resources in state.
        if db_sg_id:
            self.log(f"Found DB security group: {db_sg_id}")

            # Egress rule (all traffic to 0.0.0.0/0)
            imports_to_run.append({
                'addr': 'module.database.aws_security_group_rule.allow_all_egress',
                'import_id': f'{db_sg_id}_egress_-1_0_0_0.0.0.0/0',
                'desc': 'DB SG egress all',
            })

            # Ingress from cluster SG (PostgreSQL 5432)
            if cluster_sg_id:
                imports_to_run.append({
                    'addr': 'module.database.aws_security_group_rule.eks_cluster_postgres_ingress',
                    'import_id': f'{db_sg_id}_ingress_tcp_5432_5432_{cluster_sg_id}',
                    'desc': f'DB SG ingress TCP 5432 from cluster SG',
                })

            # Ingress from node SG (PostgreSQL 5432)
            if node_sg_id:
                imports_to_run.append({
                    'addr': 'module.database.aws_security_group_rule.eks_nodes_postgres_ingress',
                    'import_id': f'{db_sg_id}_ingress_tcp_5432_5432_{node_sg_id}',
                    'desc': f'DB SG ingress TCP 5432 from node SG',
                })
        else:
            self.log("Could not find DB security group ID - skipping DB SG rule import", 'WARN')

        # --- EKS Node Security Group Rules ---
        # The old module's rules have both cidr_blocks AND ipv6_cidr_blocks in AWS,
        # but the new config only has cidr_blocks. State mv doesn't reliably transfer
        # these rules (they end up missing from new state).
        # Fix: strip the IPv6 ranges from AWS (IPv4 stays intact), then import after push.
        mz_sg_rules = {
            'mz_ingress_pgwire': 6875,
            'mz_ingress_http': 6876,
            'mz_ingress_nlb_health_checks': 8080,
        }

        if node_sg_id:
            self.log(f"Found node security group: {node_sg_id}")
            self.log("Stripping IPv6 ranges from materialize SG rules (IPv4 rules stay intact)")

            # Only revoke the IPv6 part - IPv4 rules are NOT touched
            for rule_key, port in mz_sg_rules.items():
                ipv6_perm = {'IpProtocol': 'tcp', 'FromPort': port, 'ToPort': port,
                             'Ipv6Ranges': [{'CidrIpv6': '::/0'}]}
                self.log(f"  Revoking: TCP {port} IPv6 ::/0 on {node_sg_id}")
                if not self.dry_run:
                    result = subprocess.run(
                        ['aws', 'ec2', 'revoke-security-group-ingress',
                         '--group-id', node_sg_id,
                         '--ip-permissions', json.dumps([ipv6_perm])],
                        capture_output=True, text=True, check=False
                    )
                    if result.returncode == 0:
                        self.log(f"    ✓ Revoked")
                    else:
                        stderr = result.stderr.strip()
                        if 'InvalidPermission.NotFound' in stderr:
                            self.log(f"    ⊘ Already gone")
                        else:
                            self.log(f"    ✗ Failed: {stderr}", 'WARN')

            # Remove the mz SG rules from the local state file.
            # State mv transferred them with stale attributes (ipv6_cidr_blocks)
            # that don't match AWS after IPv6 stripping. If left in state,
            # terraform refresh fails to reconcile and plans a create (which
            # fails with "already exists"). Removing and re-importing gives
            # terraform clean, accurate attributes from AWS.
            self.log("Removing stale mz SG rule instances from local state (will re-import after push)")
            if not self.dry_run:
                try:
                    state = json.loads((self.work_dir / 'new.tfstate').read_text())
                    for resource in state.get('resources', []):
                        if (resource.get('module', '') == 'module.eks.module.eks'
                                and resource['type'] == 'aws_security_group_rule'
                                and resource['name'] == 'node'):
                            original_count = len(resource.get('instances', []))
                            resource['instances'] = [
                                inst for inst in resource.get('instances', [])
                                if inst.get('index_key') not in mz_sg_rules
                            ]
                            removed = original_count - len(resource['instances'])
                            if removed > 0:
                                self.log(f"  Removed {removed} stale mz SG rule instance(s) from state")
                                state['serial'] += 1
                                (self.work_dir / 'new.tfstate').write_text(json.dumps(state, indent=2))
                            break
                except Exception as e:
                    self.log(f"  Warning: could not remove stale instances: {e}", 'WARN')

            # Queue EKS node SG rules for fresh import after push
            for rule_key, port in mz_sg_rules.items():
                resource_addr = f'module.eks.module.eks.aws_security_group_rule.node["{rule_key}"]'
                import_id = f"{node_sg_id}_ingress_tcp_{port}_{port}_0.0.0.0/0"
                imports_to_run.append({
                    'addr': resource_addr,
                    'import_id': import_id,
                    'desc': f'EKS node SG {rule_key}',
                })
        else:
            self.log("Could not find node security group ID - skipping EKS SG rule cleanup", 'WARN')

        self.log(f"Queued {len(imports_to_run)} resource(s) for import after state push")
        return imports_to_run

    def run_imports(self, imports: List[dict]):
        """
        Run terraform import for resources that exist in AWS but aren't in state.

        IMPORTANT: This must run AFTER state push so that imports go directly
        to the remote backend. The -state flag is NOT used because it is silently
        ignored when a remote backend (S3, etc.) is configured.
        """
        if not imports:
            self.log("No imports to run")
            return

        self.log(f"Importing {len(imports)} resource(s) into remote state")

        for item in imports:
            self.log(f"  Importing: {item['desc']} ({item['import_id']})")
            if not self.dry_run:
                result = self.run_terraform(
                    ['import', item['addr'], item['import_id']],
                    cwd=self.new_dir,
                    capture=True
                )
                if result.returncode == 0:
                    self.log(f"    ✓ Imported")
                else:
                    stderr = result.stderr.strip()
                    # Resource already in state is not an error
                    if 'Resource already managed' in stderr:
                        self.log(f"    ⊘ Already in state")
                    else:
                        self.log(f"    ✗ Failed: {stderr}", 'WARN')

        self.log("Import phase complete")

    def pull_state(self, tf_dir: Path, output_file: Path):
        """Pull Terraform state to local file"""
        result = self.run_terraform(['state', 'pull'], cwd=tf_dir)

        if result.returncode == 0:
            output_file.write_text(result.stdout)
        else:
            # Create empty state
            empty_state = {
                "version": 4,
                "terraform_version": "1.5.0",
                "serial": 1,
                "lineage": "",
                "outputs": {},
                "resources": []
            }
            output_file.write_text(json.dumps(empty_state))

    def push_state(self, state_file: Path, tf_dir: Path):
        """Push local state file to Terraform backend"""
        if self.dry_run:
            return

        # Use absolute path to ensure terraform can find the file
        abs_state_file = state_file.resolve()

        result = self.run_terraform(
            ['state', 'push', str(abs_state_file)],
            cwd=tf_dir
        )

        if result.returncode != 0:
            self.log(f"Failed to push state: {result.stderr}", 'ERROR')
            sys.exit(1)

    def migrate(self):
        """Run the migration"""
        self.log_section("Automated State Migration")

        self.log(f"Old config: {self.old_dir}")
        self.log(f"New config: {self.new_dir}")
        if self.dry_run:
            self.log("DRY RUN MODE - No changes will be made", 'WARN')

        # Create working directory in new terraform directory for transparency
        self.work_dir = self.new_dir / '.migration-work'
        self.work_dir.mkdir(exist_ok=True)
        self.log(f"Working directory: {self.work_dir}")

        try:
            # Step 1: Pull states
            self.log_section("Step 1: Pulling States")

            self.log("Backing up old state...")
            backup_file = self.work_dir / f"old-state-backup-{datetime.now().strftime('%Y%m%d-%H%M%S')}.tfstate"
            result = self.run_terraform(['state', 'pull'], cwd=self.old_dir)
            if result.returncode == 0:
                backup_file.write_text(result.stdout)
                self.log(f"Backup saved to: {backup_file}")

            self.log("Pulling old state...")
            self.pull_state(self.old_dir, self.work_dir / 'old.tfstate')

            self.log("Pulling new state...")
            # Initialize if needed
            self.run_terraform(['init', '-input=false'], cwd=self.new_dir, capture=True)
            self.pull_state(self.new_dir, self.work_dir / 'new.tfstate')

            # Step 2: Analyze
            self.log_section("Step 2: Analyzing Old State")

            resources = self.get_resources(self.work_dir / 'old.tfstate')
            self.stats['total'] = len(resources)

            # Validate that old state has actual infrastructure
            if len(resources) < 10:
                self.log(f"", 'ERROR')
                self.log(f"⚠️  VALIDATION FAILED: Old state only has {len(resources)} resources", 'ERROR')
                self.log(f"", 'ERROR')
                self.log(f"A typical Materialize deployment has 100+ resources.", 'ERROR')
                self.log(f"This suggests the old state wasn't properly pulled.", 'ERROR')
                self.log(f"", 'ERROR')
                self.log(f"Common causes:", 'ERROR')
                self.log(f"  1. Old directory doesn't contain actual Materialize infrastructure", 'ERROR')
                self.log(f"  2. Remote backend not configured in old directory", 'ERROR')
                self.log(f"  3. State stored elsewhere (S3, Terraform Cloud, etc.)", 'ERROR')
                self.log(f"", 'ERROR')
                self.log(f"Solutions:", 'ERROR')
                self.log(f"  1. Ensure old directory has terraform.tfstate or backend config", 'ERROR')
                self.log(f"  2. Run 'terraform init' in old directory first", 'ERROR')
                self.log(f"  3. Run 'terraform state pull' in old directory to verify state access", 'ERROR')
                self.log(f"", 'ERROR')
                self.log(f"Cannot proceed with migration.", 'ERROR')
                sys.exit(1)

            self.log(f"Found {len(resources)} resources")

            self.module_prefix = self.detect_module_prefix(resources)
            if self.module_prefix:
                self.log(f"Detected module prefix: {self.module_prefix}")
            else:
                self.log("No module prefix detected (using root module)")

            # Step 3: Transform and move
            self.log_section("Step 3: Processing Resources")

            for resource in resources:
                new_path, rule_desc = self.transform_path(resource)

                if new_path is None:
                    if rule_desc:
                        # Intentionally skipped (e.g., data sources)
                        self.log(f"⊘ {resource}")
                        self.log(f"    {rule_desc}")
                    else:
                        # No rule found - warn
                        self.log(f"⊘ {resource}", 'WARN')
                        self.log(f"    No transformation rule", 'WARN')
                    self.stats['skipped'] += 1
                    continue

                # Check if already exists in new state
                if self.resource_exists_in_new(new_path):
                    self.log(f"⊘ {resource}")
                    self.log(f"    Already exists: {new_path}")
                    self.stats['skipped'] += 1
                    continue

                # Show transformation
                if new_path == self.strip_prefix(resource):
                    self.log(f"→ {resource}")
                else:
                    self.log(f"→ {resource}")
                    self.log(f"  ↳ {new_path}")

                # Move resource
                if self.move_resource(resource, new_path):
                    self.stats['moved'] += 1
                else:
                    self.log(f"    Failed to move", 'ERROR')
                    self.stats['failed'] += 1

            # Step 3.5: Normalize for_each keys for operator instance resources
            self.log_section("Step 3.5: Normalizing for_each Keys")
            self.log("Checking for instance_namespaces with namespace-name keys...")

            self.normalize_instance_namespace_keys()

            # Step 3.6: Validate migrated state (read-only, never deletes from state)
            self.log_section("Step 3.6: Validating Migrated State")
            self.log("Checking migrated resources for potential issues...")

            self.validate_migrated_state()

            # Step 3.7: Prepare imports (discover SG IDs, strip IPv6, queue imports)
            self.log_section("Step 3.7: Preparing Resource Imports")
            self.log("Discovering AWS resources that need importing after state push...")

            pending_imports = self.prepare_imports()

            # Step 4: Push states
            if not self.dry_run:
                self.log_section("Step 4: Updating States")

                # Only push old state if it has resources
                old_state_text = (self.work_dir / 'old.tfstate').read_text().strip()
                if old_state_text and self.stats['total'] > 0:
                    # Increment serial in old state
                    old_state = json.loads(old_state_text)
                    old_state['serial'] += 1
                    (self.work_dir / 'old-updated.tfstate').write_text(
                        json.dumps(old_state, indent=2)
                    )

                    self.log("Pushing old state...")
                    self.push_state(self.work_dir / 'old-updated.tfstate', self.old_dir)
                else:
                    self.log("Skipping old state push (no resources migrated)")

                self.log("Pushing new state...")
                self.push_state(self.work_dir / 'new.tfstate', self.new_dir)

                # Step 4.5: Run imports AFTER push
                # terraform import without -state flag goes directly to remote backend.
                # This MUST happen after push so the migrated state is already in the backend.
                if pending_imports:
                    self.log_section("Step 4.5: Importing Resources into Remote State")
                    self.run_imports(pending_imports)

            # Summary
            self.log_section("Summary")

            print(f"  Total resources: {self.stats['total']}")
            print(f"  ✅ Moved: {self.stats['moved']}")
            print(f"  ⊘ Skipped: {self.stats['skipped']}")
            print(f"  ❌ Failed: {self.stats['failed']}")

            if self.dry_run:
                print(f"\n  This was a DRY RUN. Re-run without --dry-run to apply changes.")
            else:
                print(f"\n  ✅ Migration complete!")
                print(f"  ")
                print(f"  Next steps:")
                print(f"    1. cd {self.new_dir}")
                print(f"    2. terraform plan")
                print(f"    3. Review the plan carefully")
                print(f"       - Expect 6 additions (cert-manager + NLB target bindings: kubectl_manifest adopts existing K8s resources)")
                print(f"    4. terraform apply")
                print(f"  ")
                print(f"  ℹ️  Some resources may already exist in AWS but weren't in your old state.")
                print(f"     If terraform apply fails with 'already exists' errors, import them:")
                print(f"       terraform import '<resource-path>' '<resource-id>'")
                print(f"     The error message shows the exact resource path and ID to use.")
                print(f"     See README.md troubleshooting section for examples.")

        finally:
            # Keep work directory for transparency and debugging
            # User can delete .migration-work/ manually once migration is verified
            if self.work_dir:
                self.log(f"\nWork files kept in: {self.work_dir}")
                self.log(f"You can safely delete this directory after verifying the migration")


def generate_tfvars(old_dir: Path, new_dir: Path):
    """Generate terraform.tfvars from old configuration"""
    print("Generating terraform.tfvars from old configuration...")

    # Try to read old tfvars
    old_tfvars_path = old_dir / 'terraform.tfvars'
    old_values = {}

    if old_tfvars_path.exists():
        print(f"  Found old terraform.tfvars, extracting values...")
        content = old_tfvars_path.read_text()

        # Parse simple key = "value" patterns
        import re
        for line in content.split('\n'):
            line = line.strip()
            if line and not line.startswith('#'):
                match = re.match(r'(\w+)\s*=\s*"([^"]+)"', line)
                if match:
                    old_values[match.group(1)] = match.group(2)

    # Pull state to extract values
    result = subprocess.run(
        ['terraform', 'state', 'pull'],
        cwd=old_dir,
        capture_output=True,
        text=True
    )

    if result.returncode == 0:
        try:
            state = json.loads(result.stdout)

            # Extract region from resources
            for resource in state.get('resources', []):
                if 'instances' in resource and len(resource['instances']) > 0:
                    attrs = resource['instances'][0].get('attributes', {})
                    if 'region' in attrs and 'aws_region' not in old_values:
                        old_values['aws_region'] = attrs['region']
                        break

            # Extract name prefix from VPC name
            for resource in state.get('resources', []):
                if resource.get('type') == 'aws_vpc':
                    instances = resource.get('instances', [])
                    if instances:
                        tags = instances[0].get('attributes', {}).get('tags', {})
                        name = tags.get('Name', '')
                        if name and '-vpc' in name:
                            prefix = name.replace('-vpc', '')
                            old_values['name_prefix'] = prefix
                            break
        except:
            pass

    # Build tfvars content
    tfvars_content = '''# =============================================================================
# Terraform Variables
# =============================================================================
# Auto-generated from old configuration
# Review and update as needed, especially the license_key
# =============================================================================

'''

    # Add detected values
    if 'aws_region' in old_values:
        tfvars_content += f'aws_region = "{old_values["aws_region"]}"\n'
    else:
        tfvars_content += 'aws_region = "us-east-1"  # TODO: Update this\n'

    if 'aws_profile' in old_values:
        tfvars_content += f'aws_profile = "{old_values["aws_profile"]}"\n'
    else:
        tfvars_content += 'aws_profile = "default"  # TODO: Update this\n'

    if 'name_prefix' in old_values:
        tfvars_content += f'name_prefix = "{old_values["name_prefix"]}"\n'
    else:
        tfvars_content += 'name_prefix = "materialize"  # TODO: Update this\n'

    tfvars_content += '''
# TODO: Add your Materialize license key from https://materialize.com/register
license_key = "your-license-key-here"

# CIDR blocks for access control
ingress_cidr_blocks = ["0.0.0.0/0"]
k8s_apiserver_authorized_networks = ["0.0.0.0/0"]

# Load balancer configuration
internal_load_balancer = true

# Tags
tags = {
  Environment = "production"
  ManagedBy   = "terraform"
  Project     = "materialize"
}
'''

    # Write to new directory
    output_path = new_dir / 'terraform.tfvars'
    output_path.write_text(tfvars_content)

    print(f"  ✅ Generated: {output_path}")
    print(f"\nDetected values:")
    for key, value in old_values.items():
        print(f"  - {key}: {value}")
    print(f"\n⚠️  Please review and update the generated file, especially:")
    print(f"  - license_key (required)")
    print(f"  - name_prefix (must match your existing resources)")
    print(f"  - CIDR blocks (restrict for production)")


def main():
    parser = argparse.ArgumentParser(
        description='Automated Terraform state migration tool'
    )
    parser.add_argument(
        'old_dir',
        type=Path,
        help='Path to old Terraform configuration'
    )
    parser.add_argument(
        'new_dir',
        type=Path,
        nargs='?',
        help='Path to new Terraform configuration'
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Show what would be done without making changes'
    )
    parser.add_argument(
        '--generate-tfvars',
        action='store_true',
        help='Generate terraform.tfvars from old configuration (run before migration)'
    )

    args = parser.parse_args()

    # Handle generate-tfvars mode
    if args.generate_tfvars:
        if not args.new_dir:
            print("Error: new_dir is required with --generate-tfvars")
            print("Usage: ./auto-migrate.py /old/dir /new/dir --generate-tfvars")
            sys.exit(1)
        generate_tfvars(args.old_dir, args.new_dir)
        return

    # Validate directories
    if not args.old_dir.exists():
        print(f"Error: Old directory not found: {args.old_dir}")
        sys.exit(1)

    if not args.new_dir:
        print("Error: new_dir is required for migration")
        print("Usage: ./auto-migrate.py /old/dir /new/dir [--dry-run]")
        print("   or: ./auto-migrate.py /old/dir /new/dir --generate-tfvars")
        sys.exit(1)

    if not args.new_dir.exists():
        print(f"Error: New directory not found: {args.new_dir}")
        sys.exit(1)

    # Run migration
    migrator = StateMigrator(args.old_dir, args.new_dir, args.dry_run)
    migrator.migrate()


if __name__ == '__main__':
    main()
