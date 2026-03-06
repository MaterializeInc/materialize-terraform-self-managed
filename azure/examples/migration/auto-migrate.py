#!/usr/bin/env python3
"""
Automated Terraform State Migration Tool for Azure

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
        """
        return [
            # =================================================================
            # Networking — move from module to root (inline in migration config)
            # =================================================================
            MigrationRule(
                pattern=r'^module\.networking\.(.+)$',
                transform=lambda m: m.group(1),
                description="Move networking resources from module to root"
            ),

            # =================================================================
            # AKS — move from module to root (inline in migration config)
            # =================================================================
            # Rename the old system nodepool: module.aks.*.materialize → *.system
            MigrationRule(
                pattern=r'^module\.aks\.azurerm_kubernetes_cluster_node_pool\.materialize$',
                transform=lambda m: 'azurerm_kubernetes_cluster_node_pool.system',
                description="Move and rename AKS system nodepool to root"
            ),

            # Move other AKS resources to root
            MigrationRule(
                pattern=r'^module\.aks\.(.+)$',
                transform=lambda m: m.group(1),
                description="Move AKS resources from module to root"
            ),

            # =================================================================
            # Database — move from module to root (inline in migration config)
            # =================================================================
            MigrationRule(
                pattern=r'^module\.database\.(.+)$',
                transform=lambda m: m.group(1),
                description="Move database resources from module to root"
            ),

            # =================================================================
            # Materialize Nodepool — keep same paths
            # =================================================================
            MigrationRule(
                pattern=r'^(module\.materialize_nodepool\..+)$',
                transform=lambda m: m.group(1),
                description="Keep materialize nodepool path unchanged"
            ),

            # =================================================================
            # Storage — keep Azure resources, skip Key Vault and SAS token
            # =================================================================
            # Skip Key Vault (not in new module — user deletes manually)
            MigrationRule(
                pattern=r'^module\.storage\.azurerm_key_vault\..*$',
                transform=lambda m: None,
                description="Skip Key Vault (not in new module)"
            ),

            # Keep other storage resources
            MigrationRule(
                pattern=r'^(module\.storage\..+)$',
                transform=lambda m: m.group(1),
                description="Keep storage module path unchanged"
            ),

            # =================================================================
            # Certificates → cert_manager + self_signed_cluster_issuer
            # =================================================================
            # Skip self-signed cert resources (kubernetes_manifest → kubectl_manifest type change)
            # kubectl_manifest will adopt the existing K8s resources with zero disruption.
            MigrationRule(
                pattern=r'^module\.certificates\.kubernetes_manifest\.(self_signed_cluster_issuer|self_signed_root_ca_certificate|root_ca_cluster_issuer)\[0\]$',
                transform=lambda m: None,
                description="Skip self-signed cert resources (type change kubernetes_manifest→kubectl_manifest)"
            ),

            # Move cert-manager namespace (remove [0] count index)
            MigrationRule(
                pattern=r'^module\.certificates\.kubernetes_namespace\.cert_manager\[0\]$',
                transform=lambda m: 'module.cert_manager.kubernetes_namespace.cert_manager',
                description="Move cert-manager namespace to cert_manager module"
            ),

            # Move cert-manager helm release (remove [0] count index)
            MigrationRule(
                pattern=r'^module\.certificates\.helm_release\.cert_manager\[0\]$',
                transform=lambda m: 'module.cert_manager.helm_release.cert_manager',
                description="Move cert-manager helm release to cert_manager module"
            ),

            # =================================================================
            # Operator — remove [0] index (old used count, new is direct)
            # =================================================================
            # Skip metrics server (AKS has built-in)
            MigrationRule(
                pattern=r'^module\.operator\[0\]\.helm_release\.metrics_server.*$',
                transform=lambda m: None,
                description="Skip metrics server helm release (AKS has built-in)"
            ),

            # Move instance namespace to materialize_instance module
            MigrationRule(
                pattern=r'^module\.operator\[0\]\.kubernetes_namespace\.instance_namespaces\[.+?\]$',
                transform=lambda m: 'module.materialize_instance.kubernetes_namespace.instance[0]',
                description="Move instance namespace to materialize_instance module"
            ),

            # Move instance backend secret to materialize_instance module
            MigrationRule(
                pattern=r'^module\.operator\[0\]\.kubernetes_secret\.materialize_backends\[.+?\]$',
                transform=lambda m: 'module.materialize_instance.kubernetes_secret.materialize_backend',
                description="Move backend secret to materialize_instance module"
            ),

            # Skip instance manifests (type change kubernetes_manifest → kubectl_manifest)
            MigrationRule(
                pattern=r'^module\.operator\[0\]\.kubernetes_manifest\.materialize_instances\[.+?\]$',
                transform=lambda m: None,
                description="Skip Materialize instance manifest (type change kubernetes_manifest→kubectl_manifest)"
            ),

            # Skip db init jobs (not in new module)
            MigrationRule(
                pattern=r'^module\.operator\[0\]\.kubernetes_job\.db_init_job\[.+?\]$',
                transform=lambda m: None,
                description="Skip db init job (not in new module)"
            ),

            # Move operator namespaces (remove [0])
            MigrationRule(
                pattern=r'^module\.operator\[0\]\.(.+)$',
                transform=lambda m: f'module.operator.{m.group(1)}',
                description="Remove [0] index from operator module"
            ),

            # =================================================================
            # Load Balancers — remove for_each key
            # =================================================================
            MigrationRule(
                pattern=r'^module\.load_balancers\[.+?\]\.(.+)$',
                transform=lambda m: f'module.load_balancers.{m.group(1)}',
                description="Remove for_each key from load_balancers module"
            ),

            # =================================================================
            # Data sources — skip (will be recreated automatically)
            # =================================================================
            MigrationRule(
                pattern=r'^(.*\.)?data\..*$',
                transform=lambda m: None,
                description="Skip data source (will be recreated)"
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
        pattern = re.compile(r'^module\.([^.]+)\.module\.(networking|aks|database)')

        for resource in resources:
            match = pattern.match(resource)
            if match:
                prefix_name = match.group(1)
                module_name = match.group(2)

                # Skip if prefix matches module name (internal nesting)
                if prefix_name == module_name:
                    continue

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
        path_to_transform = self.strip_prefix(old_path)

        for rule in self.rules:
            match = re.match(rule.pattern, path_to_transform)
            if match:
                new_path = rule.transform(match)
                return new_path, rule.description

        return None, None

    def get_resources(self, state_file: Path) -> List[str]:
        """Get list of resources from state file by parsing JSON directly"""
        try:
            if not state_file.exists() or state_file.stat().st_size == 0:
                return []

            with open(state_file, 'r') as f:
                state = json.load(f)

            resources = []
            for resource in state.get('resources', []):
                resource_type = resource.get('type', '')
                resource_name = resource.get('name', '')
                resource_mode = resource.get('mode', 'managed')

                module_path = resource.get('module', '')
                if module_path:
                    if resource_mode == 'data':
                        full_path = f"{module_path}.data.{resource_type}.{resource_name}"
                    else:
                        full_path = f"{module_path}.{resource_type}.{resource_name}"
                else:
                    if resource_mode == 'data':
                        full_path = f"data.{resource_type}.{resource_name}"
                    else:
                        full_path = f"{resource_type}.{resource_name}"

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
                                resources.append(f'{full_path}["{index_key}"]')
                        else:
                            resources.append(full_path)

            return resources
        except Exception as e:
            if state_file.exists() and state_file.stat().st_size > 0:
                self.log(f"Error reading state file {state_file}: {e}", 'ERROR')
            return []

    def resource_exists_in_new(self, resource: str) -> bool:
        """Check if resource already exists in new state"""
        new_state = self.work_dir / 'new.tfstate'
        try:
            resources = self.get_resources(new_state)
            return resource in resources
        except:
            return False

    def move_resource(self, old_path: str, new_path: str) -> bool:
        """Move resource from old state to new state"""
        if self.dry_run:
            return True

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
            cwd=self.new_dir,
            capture=True
        )

        return result.returncode == 0

    def cleanup_old_state(self):
        """
        Remove skipped managed resources from old state.

        After state moves, skipped resources (e.g., kubernetes_manifest instances
        that can't be state-moved due to type changes) remain in old state.
        If someone runs 'terraform destroy' on the old config, these resources
        would be destroyed — including your running Materialize instance.

        This method strips all remaining managed resources from the old state,
        keeping only data sources (which are harmless). The actual Kubernetes/cloud
        resources continue running — only Terraform's ownership is removed.
        """
        if self.dry_run:
            return

        old_state_path = self.work_dir / 'old.tfstate'
        try:
            state = json.loads(old_state_path.read_text())

            original_resources = state.get('resources', [])
            managed_remaining = [
                r for r in original_resources
                if r.get('mode') != 'data'
            ]

            if not managed_remaining:
                self.log("No orphaned managed resources in old state")
                return

            # Keep only data sources
            state['resources'] = [
                r for r in original_resources
                if r.get('mode') == 'data'
            ]

            old_state_path.write_text(json.dumps(state, indent=2))

            for r in managed_remaining:
                module_path = r.get('module', '')
                resource_id = f"{r['type']}.{r['name']}"
                if module_path:
                    resource_id = f"{module_path}.{resource_id}"
                self.log(f"  Removed from old state: {resource_id}")

            self.log(f"Cleaned {len(managed_remaining)} orphaned resource(s) from old state")
            self.log(f"This prevents accidental destruction via the old config")

        except Exception as e:
            self.log(f"Warning: Could not clean up old state: {e}", 'WARN')
            self.log(f"Consider manually running 'terraform state rm' on skipped resources in old config", 'WARN')

    def validate_migrated_state(self):
        """
        Validate migrated resources in new state.

        Only inspects resources that we moved — never touches anything else.
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

                    if not attrs or attrs.get('id') is None:
                        issues.append(full_path)
                        self.log(f"⚠ Resource may have null attributes after state mv: {full_path}")
                        self.log(f"  This can happen when moving resources across module boundaries.")
                        self.log(f"  If terraform apply fails for this resource, import it manually:")
                        self.log(f"    terraform import '{full_path}' '<resource-id>'")

            if issues:
                self.log(f"\nFound {len(issues)} resource(s) that may need attention after apply.")
                self.log(f"These were NOT removed from state — review terraform apply output.")
            else:
                self.log("✓ All migrated resources look valid")

        except Exception as e:
            self.log(f"Error during state validation: {e}", 'WARN')

    def pull_state(self, tf_dir: Path, output_file: Path):
        """Pull Terraform state to local file"""
        result = self.run_terraform(['state', 'pull'], cwd=tf_dir)

        if result.returncode != 0:
            self.log(f"Failed to pull state from {tf_dir}: {result.stderr}", 'ERROR')
            self.log(f"Ensure the directory is initialized (terraform init) and the backend is accessible.", 'ERROR')
            sys.exit(1)

        output_file.write_text(result.stdout)

    def push_state(self, state_file: Path, tf_dir: Path):
        """Push local state file to Terraform backend"""
        if self.dry_run:
            return

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
        self.log_section("Automated State Migration (Azure)")

        self.log(f"Old config: {self.old_dir}")
        self.log(f"New config: {self.new_dir}")
        if self.dry_run:
            self.log("DRY RUN MODE — No changes will be made", 'WARN')

        # Create working directory
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
                self.log(f"A typical Materialize deployment has 30+ resources.", 'ERROR')
                self.log(f"This suggests the old state wasn't properly pulled.", 'ERROR')
                self.log(f"", 'ERROR')
                self.log(f"Common causes:", 'ERROR')
                self.log(f"  1. Old directory doesn't contain actual Materialize infrastructure", 'ERROR')
                self.log(f"  2. Remote backend not configured in old directory", 'ERROR')
                self.log(f"  3. State stored elsewhere (Azure Storage, Terraform Cloud, etc.)", 'ERROR')
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
                        self.log(f"⊘ {resource}")
                        self.log(f"    {rule_desc}")
                    else:
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

            # Step 3.5: Validate migrated state
            self.log_section("Step 3.5: Validating Migrated State")
            self.log("Checking migrated resources for potential issues...")
            self.validate_migrated_state()

            # Step 3.6: Clean up old state
            self.log_section("Step 3.6: Cleaning Up Old State")
            self.log("Removing skipped resources from old state to prevent accidental destruction...")
            self.cleanup_old_state()

            # Step 4: Push states
            if not self.dry_run:
                self.log_section("Step 4: Updating States")

                old_state_text = (self.work_dir / 'old.tfstate').read_text().strip()
                if old_state_text and self.stats['total'] > 0:
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
                print(f"       - Expect additions: self-signed cert resources + materialize instance (kubectl_manifest adopts existing K8s resources)")
                print(f"       - Expect additions: federated identity credential (new workload identity)")
                print(f"    4. terraform apply")
                print(f"  ")
                print(f"  ℹ️  Some resources may already exist in Azure but weren't in your old state.")
                print(f"     If terraform apply fails with 'already exists' errors, import them:")
                print(f"       terraform import '<resource-path>' '<resource-id>'")
                print(f"     The error message shows the exact resource path and ID to use.")
                print(f"     See README.md troubleshooting section for examples.")

        finally:
            if self.work_dir:
                self.log(f"\nWork files kept in: {self.work_dir}")
                self.log(f"You can safely delete this directory after verifying the migration")


def generate_tfvars(old_dir: Path, new_dir: Path):
    """Generate terraform.tfvars from old configuration"""
    print("Generating terraform.tfvars from old configuration...")

    old_tfvars_path = old_dir / 'terraform.tfvars'
    old_values = {}

    if old_tfvars_path.exists():
        print(f"  Found old terraform.tfvars, extracting values...")
        content = old_tfvars_path.read_text()

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

            # Extract location from AKS cluster
            for resource in state.get('resources', []):
                if resource.get('type') == 'azurerm_kubernetes_cluster':
                    instances = resource.get('instances', [])
                    if instances:
                        attrs = instances[0].get('attributes', {})
                        if 'location' in attrs and 'location' not in old_values:
                            old_values['location'] = attrs['location']
                        break

            # Extract prefix from VNet name
            for resource in state.get('resources', []):
                if resource.get('type') == 'azurerm_virtual_network':
                    instances = resource.get('instances', [])
                    if instances:
                        name = instances[0].get('attributes', {}).get('name', '')
                        if name and '-vnet' in name:
                            prefix = name.replace('-vnet', '')
                            old_values['name_prefix'] = prefix
                            break

            # Extract resource group
            for resource in state.get('resources', []):
                if resource.get('type') == 'azurerm_kubernetes_cluster':
                    instances = resource.get('instances', [])
                    if instances:
                        rg = instances[0].get('attributes', {}).get('resource_group_name', '')
                        if rg:
                            old_values['resource_group_name'] = rg
                            break
        except:
            pass

    # Build tfvars content
    tfvars_content = '''# =============================================================================
# Terraform Variables
# =============================================================================
# Auto-generated from old configuration
# Review and update as needed, especially the license_key and passwords
# =============================================================================

'''

    if 'location' in old_values:
        tfvars_content += f'location = "{old_values["location"]}"\n'
    else:
        tfvars_content += 'location = "eastus2"  # TODO: Update this\n'

    if 'resource_group_name' in old_values:
        tfvars_content += f'resource_group_name = "{old_values["resource_group_name"]}"\n'
    else:
        tfvars_content += 'resource_group_name = "your-rg"  # TODO: Update this\n'

    if 'name_prefix' in old_values:
        tfvars_content += f'name_prefix = "{old_values["name_prefix"]}"\n'
    else:
        tfvars_content += 'name_prefix = "materialize"  # TODO: Update this\n'

    tfvars_content += '''
# TODO: Set your Azure subscription ID
subscription_id = "your-subscription-id"

# TODO: Add your Materialize license key from https://materialize.com/register
license_key = "your-license-key-here"

# TODO: Set your Materialize instance name
# Run: kubectl get materialize -A -o jsonpath='{.items[0].metadata.name}'
materialize_instance_name = "your-instance-name"

# TODO: Set your existing database password
old_db_password = "your-db-password"

# TODO: Set your existing mz_system user password
external_login_password_mz_system = "your-mz-system-password"

# Load balancer configuration
internal_load_balancer = true

# Tags
tags = {
  managed_by = "terraform"
  module     = "materialize"
}
'''

    output_path = new_dir / 'terraform.tfvars'
    output_path.write_text(tfvars_content)

    print(f"  ✅ Generated: {output_path}")
    print(f"\nDetected values:")
    for key, value in old_values.items():
        print(f"  - {key}: {value}")
    print(f"\n⚠️  Please review and update the generated file, especially:")
    print(f"  - subscription_id (required)")
    print(f"  - license_key (required)")
    print(f"  - name_prefix (must match your existing resources)")
    print(f"  - old_db_password (required)")
    print(f"  - external_login_password_mz_system (required)")
    print(f"  - materialize_instance_name (required)")


def main():
    parser = argparse.ArgumentParser(
        description='Automated Terraform state migration tool for Azure'
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
