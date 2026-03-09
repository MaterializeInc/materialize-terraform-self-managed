#!/usr/bin/env python3
"""
Base module for Terraform State Migration Tools.

Provides the shared BaseStateMigrator class and MigrationRule dataclass
used by cloud-specific migration scripts (AWS, Azure, GCP).

Each cloud provider's auto-migrate.py subclasses BaseStateMigrator and
only defines the provider-specific parts:
  - Migration rules (_build_rules)
  - Module detection names (module_detection_names)
  - Tfvars generation (generate_tfvars)
  - Completion hints (_completion_hints)
"""

import abc
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Optional, List, Tuple, Type


@dataclass
class MigrationRule:
    """A rule for transforming old resource paths to new paths"""
    pattern: str
    transform: callable
    description: str


class BaseStateMigrator(abc.ABC):
    """
    Base class for Terraform state migration across cloud providers.

    Subclasses must implement:
      - provider_name (class attribute): e.g., "GCP", "Azure", "AWS"
      - module_detection_names (class attribute): tuple of module names for prefix detection
      - expected_resource_count_hint (class attribute): e.g., "25+"
      - state_backend_hint (class attribute): e.g., "GCS bucket, Terraform Cloud, etc."
      - _build_rules(): returns list of MigrationRule
      - generate_tfvars(old_dir, new_dir): classmethod for tfvars generation
      - _completion_hints(): returns list of hint strings for post-migration output

    Subclasses may override for extra migration steps:
      - _post_transform(): called after resource moves (before validation)
      - _pre_push(): called after validation/cleanup, before state push
      - _post_push(): called after state push
    """

    # -- Class attributes to override --
    provider_name: str = "Unknown"
    module_detection_names: tuple = ("networking", "database")
    expected_resource_count_hint: str = "25+"
    state_backend_hint: str = "remote backend, Terraform Cloud, etc."

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

    # =====================================================================
    # Abstract methods — must be implemented by subclasses
    # =====================================================================

    @abc.abstractmethod
    def _build_rules(self) -> List[MigrationRule]:
        """
        Build transformation rules for resource path mapping.

        Rules are evaluated in order. The first matching rule wins.
        Return None from a rule's transform to skip the resource.
        """
        ...

    @staticmethod
    @abc.abstractmethod
    def generate_tfvars(old_dir: Path, new_dir: Path):
        """Generate terraform.tfvars from old configuration."""
        ...

    @abc.abstractmethod
    def _completion_hints(self) -> List[str]:
        """
        Return cloud-specific hint lines for the post-migration summary.

        Example:
            return [
                "- Expect additions: self-signed cert resources + materialize instance",
                "- Expect additions: firewall rules for load balancers",
            ]
        """
        ...

    # =====================================================================
    # Hook methods — override in subclasses for extra steps
    # =====================================================================

    def _post_transform(self):
        """Called after all resources are transformed and moved.

        Override for extra steps like normalizing for_each keys (AWS).
        """
        pass

    def _pre_push(self):
        """Called after validation and cleanup, before state push.

        Override for extra pre-push steps like preparing imports (AWS).
        """
        pass

    def _post_push(self):
        """Called after state push completes.

        Override for post-push steps like running imports (AWS).
        """
        pass

    # =====================================================================
    # Shared methods — identical across all providers
    # =====================================================================

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
        names = '|'.join(self.module_detection_names)
        pattern = re.compile(rf'^module\.([^.]+)\.module\.({names})')

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
        """Get list of resources from state file by parsing JSON directly.

        Raises on parse errors — callers that need tolerance should catch exceptions.
        """
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

    def resource_exists_in_new(self, resource: str) -> bool:
        """Check if resource already exists in new state"""
        new_state = self.work_dir / 'new.tfstate'
        try:
            resources = self.get_resources(new_state)
            return resource in resources
        except Exception:
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

    # =====================================================================
    # Main migration flow — template method
    # =====================================================================

    def migrate(self):
        """Run the full migration workflow."""
        title = f"Automated State Migration ({self.provider_name})"
        self.log_section(title)

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

            self.log("Pulling old state...")
            self.pull_state(self.old_dir, self.work_dir / 'old.tfstate')

            self.log("Backing up old state...")
            backup_file = self.work_dir / f"old-state-backup-{datetime.now().strftime('%Y%m%d-%H%M%S')}.tfstate"
            shutil.copy2(self.work_dir / 'old.tfstate', backup_file)
            self.log(f"Backup saved to: {backup_file}")

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
                self.log(f"A typical Materialize deployment has {self.expected_resource_count_hint} resources.", 'ERROR')
                self.log(f"This suggests the old state wasn't properly pulled.", 'ERROR')
                self.log(f"", 'ERROR')
                self.log(f"Common causes:", 'ERROR')
                self.log(f"  1. Old directory doesn't contain actual Materialize infrastructure", 'ERROR')
                self.log(f"  2. Remote backend not configured in old directory", 'ERROR')
                self.log(f"  3. State stored elsewhere ({self.state_backend_hint})", 'ERROR')
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

            # Post-transform hook (e.g., AWS normalizes for_each keys)
            self._post_transform()

            # Validate migrated state
            self.log_section("Validating Migrated State")
            self.log("Checking migrated resources for potential issues...")
            self.validate_migrated_state()

            # Clean up old state
            self.log_section("Cleaning Up Old State")
            self.log("Removing skipped resources from old state to prevent accidental destruction...")
            self.cleanup_old_state()

            # Pre-push hook (e.g., AWS prepares imports)
            self._pre_push()

            # Step 4: Push states
            if not self.dry_run:
                self.log_section("Updating States")

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

                # Post-push hook (e.g., AWS runs imports)
                self._post_push()

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
                for hint in self._completion_hints():
                    print(f"       {hint}")
                print(f"    4. terraform apply")
                print(f"  ")
                print(f"  ℹ️  Some resources may already exist in {self.provider_name} but weren't in your old state.")
                print(f"     If terraform apply fails with 'already exists' errors, import them:")
                print(f"       terraform import '<resource-path>' '<resource-id>'")
                print(f"     The error message shows the exact resource path and ID to use.")
                print(f"     See README.md troubleshooting section for examples.")

        finally:
            if self.work_dir:
                self.log(f"\nWork files kept in: {self.work_dir}")
                self.log(f"You can safely delete this directory after verifying the migration")


# =========================================================================
# Shared tfvars helper
# =========================================================================

def parse_old_tfvars(old_dir: Path) -> dict:
    """Parse simple key = "value" patterns from old terraform.tfvars."""
    old_values = {}
    old_tfvars_path = old_dir / 'terraform.tfvars'

    if old_tfvars_path.exists():
        print(f"  Found old terraform.tfvars, extracting values...")
        content = old_tfvars_path.read_text()

        for line in content.split('\n'):
            line = line.strip()
            if line and not line.startswith('#'):
                match = re.match(r'(\w+)\s*=\s*"([^"]+)"', line)
                if match:
                    old_values[match.group(1)] = match.group(2)

    return old_values


def pull_state_json(old_dir: Path) -> Optional[dict]:
    """Pull terraform state from old directory and return parsed JSON."""
    result = subprocess.run(
        ['terraform', 'state', 'pull'],
        cwd=old_dir,
        capture_output=True,
        text=True
    )

    if result.returncode == 0:
        try:
            return json.loads(result.stdout)
        except:
            pass
    return None


# =========================================================================
# Shared CLI entry point
# =========================================================================

def run_main(migrator_class: Type[BaseStateMigrator]):
    """Shared CLI entry point for all cloud-specific migration scripts."""
    parser = argparse.ArgumentParser(
        description=f'Automated Terraform state migration tool for {migrator_class.provider_name}'
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
        migrator_class.generate_tfvars(args.old_dir, args.new_dir)
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
    migrator = migrator_class(args.old_dir, args.new_dir, args.dry_run)
    migrator.migrate()
