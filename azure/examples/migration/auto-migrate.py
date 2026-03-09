#!/usr/bin/env python3
"""
Automated Terraform State Migration Tool for Azure

Migrates resources from the old monolithic Azure module to the new
modular structure. Uses the shared BaseStateMigrator from scripts/.

Usage:
    ./auto-migrate.py /path/to/old/terraform /path/to/new/terraform [--dry-run]
"""

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


class AzureStateMigrator(BaseStateMigrator):
    provider_name = "Azure"
    module_detection_names = ("networking", "aks", "database")
    expected_resource_count_hint = "30+"
    state_backend_hint = "Azure Storage, Terraform Cloud, etc."

    def _build_rules(self) -> List[MigrationRule]:
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

    def _completion_hints(self) -> List[str]:
        return [
            "- Expect additions: self-signed cert resources + materialize instance (kubectl_manifest adopts existing K8s resources)",
            "- Expect additions: federated identity credential (new workload identity)",
        ]

    @staticmethod
    def generate_tfvars(old_dir: Path, new_dir: Path):
        """Generate terraform.tfvars from old Azure configuration"""
        print("Generating terraform.tfvars from old configuration...")

        old_values = parse_old_tfvars(old_dir)
        state = pull_state_json(old_dir)

        if state:
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


if __name__ == '__main__':
    run_main(AzureStateMigrator)
