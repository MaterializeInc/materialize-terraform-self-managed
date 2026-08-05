## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 3.75.0, < 4.76.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 2.5.0, < 2.18.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.10.0, < 2.39.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.5.0, < 3.10.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 3.75.0, < 4.76.0 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.5.0, < 3.10.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_monitoring"></a> [monitoring](#module\_monitoring) | github.com/MaterializeInc/materialize-monitoring//terraform/modules/materialize-monitoring | materialize-monitoring%2Fv0.12.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_federated_identity_credential.telemetry](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/federated_identity_credential) | resource |
| [azurerm_role_assignment.telemetry](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_storage_account.telemetry](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account) | resource |
| [azurerm_storage_container.telemetry](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_container) | resource |
| [azurerm_user_assigned_identity.telemetry](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [random_string.unique](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_account_replication_type"></a> [account\_replication\_type](#input\_account\_replication\_type) | Replication for the telemetry storage account. LRS is the default because both backends treat object storage as replaceable — Loki re-ingests and Thanos re-uploads — so paying for ZRS buys less here than for the Materialize persist account. | `string` | `"LRS"` | no |
| <a name="input_additional_values"></a> [additional\_values](#input\_additional\_values) | Raw YAML documents appended to the Helm values, last, so they override everything the modules compute. | `list(string)` | `[]` | no |
| <a name="input_chart_version"></a> [chart\_version](#input\_chart\_version) | Override the materialize-monitoring chart version. Leave null to use the version the pinned module ships with — the two are one release. | `string` | `null` | no |
| <a name="input_create_namespace"></a> [create\_namespace](#input\_create\_namespace) | Whether the monitoring module creates the namespace. False by default because the operator module already creates `monitoring`. | `bool` | `false` | no |
| <a name="input_grafana_admin_password"></a> [grafana\_admin\_password](#input\_grafana\_admin\_password) | Grafana admin password. Generated when null. | `string` | `null` | no |
| <a name="input_install_metrics_server"></a> [install\_metrics\_server](#input\_install\_metrics\_server) | Install metrics-server as part of the monitoring stack. Set true when the operator module has `install_metrics_server = false`, or the Materialize Console loses cluster metrics. | `bool` | `false` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region for the storage account and identities. | `string` | n/a | yes |
| <a name="input_loki_container_name"></a> [loki\_container\_name](#input\_loki\_container\_name) | Blob container for Loki chunks and rules. | `string` | `"mzmon-loki"` | no |
| <a name="input_materialize_instance_namespace"></a> [materialize\_instance\_namespace](#input\_materialize\_instance\_namespace) | Namespace the Materialize instance runs in. | `string` | `"materialize-environment"` | no |
| <a name="input_materialize_operator_namespace"></a> [materialize\_operator\_namespace](#input\_materialize\_operator\_namespace) | Namespace the Materialize operator runs in. | `string` | `"materialize"` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace the monitoring stack is installed into. Also the namespace half of every federated-credential subject. | `string` | `"monitoring"` | no |
| <a name="input_network_rules_default_action"></a> [network\_rules\_default\_action](#input\_network\_rules\_default\_action) | Default action for the storage account's network rules when `subnets` is set. | `string` | `"Deny"` | no |
| <a name="input_node_selector"></a> [node\_selector](#input\_node\_selector) | Node selector for the centralized monitoring workloads. Not applied to the Alloy agent DaemonSet, which must reach every node. | `map(string)` | `{}` | no |
| <a name="input_oidc_issuer_url"></a> [oidc\_issuer\_url](#input\_oidc\_issuer\_url) | The AKS cluster's OIDC issuer URL, from the `aks` module. Requires `oidc_issuer_enabled` and `workload_identity_enabled` on the cluster. | `string` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefix for the storage account and identity names this module creates. | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group holding the storage account and identities. | `string` | n/a | yes |
| <a name="input_sizing"></a> [sizing](#input\_sizing) | Deployment size: small, medium, or large. The chart's defaults are medium. | `string` | `"medium"` | no |
| <a name="input_storage_class"></a> [storage\_class](#input\_storage\_class) | StorageClass for the PVC-backed monitoring workloads (Alertmanager, the Loki ruler, and Thanos receive/compactor/store-gateway). Null uses the cluster default; AKS ships `managed-csi`. | `string` | `null` | no |
| <a name="input_subnets"></a> [subnets](#input\_subnets) | Subnet IDs allowed to reach the storage account. Empty leaves the account open to the configured default action, which is what a cluster without service endpoints needs. | `list(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the resources this module creates. | `map(string)` | `{}` | no |
| <a name="input_thanos_container_name"></a> [thanos\_container\_name](#input\_thanos\_container\_name) | Blob container for Thanos blocks. | `string` | `"mzmon-thanos"` | no |
| <a name="input_tolerations"></a> [tolerations](#input\_tolerations) | Tolerations for the monitoring workloads, including the Alloy agent DaemonSet. | <pre>list(object({<br/>    key      = optional(string)<br/>    operator = optional(string, "Equal")<br/>    value    = optional(string)<br/>    effect   = optional(string)<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_grafana_admin_password"></a> [grafana\_admin\_password](#output\_grafana\_admin\_password) | Grafana admin password. |
| <a name="output_grafana_url"></a> [grafana\_url](#output\_grafana\_url) | In-cluster URL for Grafana. Grafana is ClusterIP-only today, so reaching it means a port-forward. |
| <a name="output_identity_client_ids"></a> [identity\_client\_ids](#output\_identity\_client\_ids) | User-assigned identity client IDs, by backend. One per backend, each scoped to its own container. |
| <a name="output_logs_container"></a> [logs\_container](#output\_logs\_container) | Blob container holding Loki chunks and the ruler's state. |
| <a name="output_logs_url"></a> [logs\_url](#output\_logs\_url) | Loki read endpoint. |
| <a name="output_metrics_container"></a> [metrics\_container](#output\_metrics\_container) | Blob container holding Thanos blocks. |
| <a name="output_metrics_url"></a> [metrics\_url](#output\_metrics\_url) | Thanos Query endpoint. Prometheus-API-compatible. |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace the monitoring stack is installed into. |
| <a name="output_storage_account_name"></a> [storage\_account\_name](#output\_storage\_account\_name) | Storage account holding both telemetry containers. |
| <a name="output_workload_identity_subjects"></a> [workload\_identity\_subjects](#output\_workload\_identity\_subjects) | The `system:serviceaccount:<namespace>:<sa>` subjects the federated credentials trust. Emitted so a mismatch against the chart's rendered ServiceAccount names is visible rather than derived. |
