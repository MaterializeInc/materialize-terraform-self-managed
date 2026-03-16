#!/usr/bin/env python3
"""
Automated Terraform State Migration Tool for AWS

Migrates resources from the old monolithic AWS module to the new
modular structure. Uses the shared BaseStateMigrator from scripts/.

AWS-specific extras:
  - Normalizes instance_namespaces for_each keys after migration
  - Prepares and runs imports for SG rules and DB SG rules
  - Strips IPv6 ranges from EKS node SG rules before import

Usage:
    ./auto-migrate.py /path/to/old/terraform /path/to/new/terraform [--dry-run]
"""

import json
import subprocess
import sys
from pathlib import Path
from typing import List

# Add scripts/ to path for shared base module
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'scripts'))

from migrate_base import (
    BaseStateMigrator,
    MigrationRule,
    parse_old_tfvars,
    pull_state_json,
    run_main,
)


class AWSStateMigrator(BaseStateMigrator):
    provider_name = "AWS"
    module_detection_names = ("networking", "eks", "database")
    expected_resource_count_hint = "100+"
    state_backend_hint = "S3, Terraform Cloud, etc."

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._pending_imports = []

    def _build_rules(self) -> List[MigrationRule]:
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
            MigrationRule(
                pattern=r'^module\.eks\.module\.eks\.module\.eks_managed_node_group\[.+?\]\.(.+)$',
                transform=lambda m: f'module.base_node_group.module.node_group.{m.group(1)}',
                description="Migrate EKS internal managed node group to base_node_group"
            ),

            # Move Materialize instance resources from operator module to root level
            MigrationRule(
                pattern=r'^module\.operator\.kubernetes_manifest\.materialize_instances(\[.+?\])$',
                transform=lambda m: f'kubernetes_manifest.materialize_instances{m.group(1)}',
                description="Move Materialize instance manifests from operator to root"
            ),

            # Move Materialize instance data sources from operator module to root level
            MigrationRule(
                pattern=r'^module\.operator\.data\.kubernetes_resource\.materialize_instances(\[.+?\])$',
                transform=lambda m: f'data.kubernetes_resource.materialize_instances{m.group(1)}',
                description="Move Materialize instance data sources from operator to root"
            ),

            # Move instance namespaces from operator module to root level
            MigrationRule(
                pattern=r'^module\.operator\.kubernetes_namespace\.instance_namespaces(\[.+?\])$',
                transform=lambda m: f'kubernetes_namespace.instance_namespaces{m.group(1)}',
                description="Move instance namespaces from operator to root"
            ),

            # Move backend secrets from operator module to root level
            MigrationRule(
                pattern=r'^module\.operator\.kubernetes_secret\.materialize_backends(\[.+?\])$',
                transform=lambda m: f'kubernetes_secret.materialize_backends{m.group(1)}',
                description="Move backend secrets from operator to root"
            ),

            # Skip db init jobs — already ran during initial setup, not needed after migration
            MigrationRule(
                pattern=r'^module\.operator\.kubernetes_job\.db_init_job\[.+?\]$',
                transform=lambda m: None,
                description="Skip completed db init job (one-time setup, already ran)"
            ),

            # Skip NLB TargetGroupBinding resources (kubernetes_manifest → kubectl_manifest type change)
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

            # Skip data sources
            MigrationRule(
                pattern=r'^(.*\.)?data\..*$',
                transform=lambda m: None,
                description="Skip data source (will be recreated)"
            ),

            # Skip old cloudwatch log groups
            MigrationRule(
                pattern=r'^aws_cloudwatch_log_group\.materialize\[.*\]$',
                transform=lambda m: None,
                description="Skip old cloudwatch log group"
            ),
        ]

    # =================================================================
    # AWS-specific hook overrides
    # =================================================================

    def _post_transform(self):
        """Normalize instance_namespaces for_each keys after resource moves."""
        self.log_section("Normalizing for_each Keys")
        self.log("Checking for instance_namespaces with namespace-name keys...")
        self._normalize_instance_namespace_keys()

    def _pre_push(self):
        """Prepare resource imports (discover SG IDs, strip IPv6)."""
        self.log_section("Preparing Resource Imports")
        self.log("Discovering AWS resources that need importing after state push...")
        self._pending_imports = self._prepare_imports()

    def _post_push(self):
        """Run terraform import for SG rules after state push."""
        if self._pending_imports:
            self.log_section("Importing Resources into Remote State")
            self._run_imports(self._pending_imports)

    def _completion_hints(self) -> List[str]:
        return [
            "- Expect 6 additions (cert-manager + NLB target bindings: kubectl_manifest adopts existing K8s resources)",
        ]

    # =================================================================
    # AWS-specific methods
    # =================================================================

    def _normalize_instance_namespace_keys(self):
        """
        Normalize instance_namespaces keys from namespace names to instance names.

        The old operator module used namespace names as keys for instance_namespaces,
        but instance names for other resources. This normalizes to use instance names consistently.
        """
        try:
            state = json.loads((self.work_dir / 'new.tfstate').read_text())

            # Build mapping: namespace_name -> instance_name
            namespace_to_instance = {}

            for resource in state.get('resources', []):
                if (resource.get('module') == 'module.operator' and
                    resource['type'] == 'kubernetes_manifest' and
                    resource['name'] == 'materialize_instances'):

                    for instance in resource.get('instances', []):
                        if 'index_key' in instance and 'attributes' in instance:
                            instance_name = instance['index_key']
                            manifest_attr = instance['attributes'].get('manifest', {})

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

            state_modified = False

            for resource in state.get('resources', []):
                if (resource.get('module') == 'module.operator' and
                    resource['type'] == 'kubernetes_namespace' and
                    resource['name'] == 'instance_namespaces'):

                    existing_keys = {inst.get('index_key') for inst in resource.get('instances', [])}
                    instances_to_keep = []

                    for instance in resource.get('instances', []):
                        if 'index_key' in instance:
                            current_key = instance['index_key']

                            if current_key in namespace_to_instance:
                                instance_name = namespace_to_instance[current_key]

                                if current_key != instance_name:
                                    old_addr = f'module.operator.kubernetes_namespace.instance_namespaces[{json.dumps(current_key)}]'
                                    new_addr = f'module.operator.kubernetes_namespace.instance_namespaces[{json.dumps(instance_name)}]'

                                    self.log(f"→ Normalizing namespace key:")
                                    self.log(f"  {old_addr}")
                                    self.log(f"  ↳ {new_addr}")

                                    if not self.dry_run:
                                        if instance_name in existing_keys and instance_name != current_key:
                                            self.log(f"  ⊘ Skipped (target key already exists)")
                                            continue
                                        else:
                                            instance['index_key'] = instance_name
                                            self.log(f"  ✓ Normalized")
                                            state_modified = True

                        instances_to_keep.append(instance)

                    if not self.dry_run and len(instances_to_keep) != len(resource.get('instances', [])):
                        resource['instances'] = instances_to_keep
                        state_modified = True

            if state_modified and not self.dry_run:
                self.log("Saving normalized state...")
                state['serial'] += 1
                (self.work_dir / 'new.tfstate').write_text(json.dumps(state, indent=2))
                self.log("✓ State saved")

        except Exception as e:
            self.log(f"Error during key normalization: {e}", 'WARN')
            self.log("This is non-fatal - you may need to manually normalize keys")

    def _prepare_imports(self) -> list:
        """
        Discover SG IDs, strip IPv6 from AWS, and return imports to run after push.
        """
        imports_to_run = []

        try:
            new_state = json.loads((self.work_dir / 'new.tfstate').read_text())
        except Exception as e:
            self.log(f"Error reading state files: {e}", 'WARN')
            return imports_to_run

        # Discover Security Group IDs from state
        db_sg_id = None
        cluster_sg_id = None
        node_sg_id = None

        for resource in new_state.get('resources', []):
            module = resource.get('module', '')

            if ('database' in module and resource['type'] == 'aws_db_instance'
                    and resource['name'] == 'this'):
                for inst in resource.get('instances', []):
                    vpc_sgs = inst.get('attributes', {}).get('vpc_security_group_ids', [])
                    if vpc_sgs:
                        db_sg_id = vpc_sgs[0]

            if (module == 'module.eks.module.eks' and resource['type'] == 'aws_security_group'
                    and resource['name'] == 'cluster'):
                for inst in resource.get('instances', []):
                    cluster_sg_id = inst.get('attributes', {}).get('id')

            if (module == 'module.eks.module.eks' and resource['type'] == 'aws_security_group'
                    and resource['name'] == 'node'):
                for inst in resource.get('instances', []):
                    node_sg_id = inst.get('attributes', {}).get('id')

        # Database Security Group Rules
        if db_sg_id:
            self.log(f"Found DB security group: {db_sg_id}")

            imports_to_run.append({
                'addr': 'module.database.aws_security_group_rule.allow_all_egress',
                'import_id': f'{db_sg_id}_egress_-1_0_0_0.0.0.0/0',
                'desc': 'DB SG egress all',
            })

            if cluster_sg_id:
                imports_to_run.append({
                    'addr': 'module.database.aws_security_group_rule.eks_cluster_postgres_ingress',
                    'import_id': f'{db_sg_id}_ingress_tcp_5432_5432_{cluster_sg_id}',
                    'desc': f'DB SG ingress TCP 5432 from cluster SG',
                })

            if node_sg_id:
                imports_to_run.append({
                    'addr': 'module.database.aws_security_group_rule.eks_nodes_postgres_ingress',
                    'import_id': f'{db_sg_id}_ingress_tcp_5432_5432_{node_sg_id}',
                    'desc': f'DB SG ingress TCP 5432 from node SG',
                })
        else:
            self.log("Could not find DB security group ID - skipping DB SG rule import", 'WARN')

        # EKS Node Security Group Rules — strip IPv6 and re-import
        mz_sg_rules = {
            'mz_ingress_pgwire': 6875,
            'mz_ingress_http': 6876,
            'mz_ingress_nlb_health_checks': 8080,
        }

        if node_sg_id:
            self.log(f"Found node security group: {node_sg_id}")
            self.log("Stripping IPv6 ranges from materialize SG rules (IPv4 rules stay intact)")

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

            # Remove stale mz SG rule instances from local state
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

    def _run_imports(self, imports: list):
        """Run terraform import for resources that exist in AWS but aren't in state."""
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
                    if 'Resource already managed' in stderr:
                        self.log(f"    ⊘ Already in state")
                    else:
                        self.log(f"    ✗ Failed: {stderr}", 'WARN')

        self.log("Import phase complete")

    @staticmethod
    def generate_tfvars(old_dir: Path, new_dir: Path):
        """Generate terraform.tfvars from old AWS configuration"""
        print("Generating terraform.tfvars from old configuration...")

        old_values = parse_old_tfvars(old_dir)
        state = pull_state_json(old_dir)

        if state:
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

        # Build tfvars content
        tfvars_content = '''# =============================================================================
# Terraform Variables
# =============================================================================
# Auto-generated from old configuration
# Review and update as needed, especially the license_key
# =============================================================================

'''

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


if __name__ == '__main__':
    run_main(AWSStateMigrator)
