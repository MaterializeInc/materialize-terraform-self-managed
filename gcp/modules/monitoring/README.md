## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 7.22, < 8 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 2.5.0, < 2.18.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.10.0, < 2.39.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.0.0, < 3.10.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_google"></a> [google](#provider\_google) | >= 7.22, < 8 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_monitoring"></a> [monitoring](#module\_monitoring) | github.com/MaterializeInc/materialize-monitoring//terraform/modules/materialize-monitoring | materialize-monitoring/v0.10.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [google_project_iam_member.gateway_metric_writer](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_service_account.gateway](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_service_account.telemetry](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_service_account_iam_member.gateway_workload_identity](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_member) | resource |
| [google_service_account_iam_member.workload_identity](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_member) | resource |
| [google_storage_bucket.telemetry](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket) | resource |
| [google_storage_bucket_iam_member.telemetry](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_iam_member) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_additional_values"></a> [additional\_values](#input\_additional\_values) | Raw YAML documents appended to the Helm values, last, so they override everything the modules compute. | `list(string)` | `[]` | no |
| <a name="input_bucket_force_destroy"></a> [bucket\_force\_destroy](#input\_bucket\_force\_destroy) | Allow Terraform to delete non-empty buckets. Leave false outside throwaway environments — destroying it takes the telemetry with it. | `bool` | `false` | no |
| <a name="input_chart_version"></a> [chart\_version](#input\_chart\_version) | Override the materialize-monitoring chart version. Leave null to use the version the pinned module ships with — the two are one release. | `string` | `null` | no |
| <a name="input_create_namespace"></a> [create\_namespace](#input\_create\_namespace) | Whether the monitoring module creates the namespace. False by default because the operator module already creates `monitoring`. | `bool` | `false` | no |
| <a name="input_enable_bucket_versioning"></a> [enable\_bucket\_versioning](#input\_enable\_bucket\_versioning) | Enable versioning on the telemetry buckets. Versioning is the disaster-recovery primitive for both Loki and Thanos, neither of which has a native snapshot. | `bool` | `true` | no |
| <a name="input_enable_google_cloud_metrics"></a> [enable\_google\_cloud\_metrics](#input\_enable\_google\_cloud\_metrics) | Also export metrics to Google Cloud Monitoring from the Alloy gateway. Thanos is unaffected.<br/><br/>Creates a service account with `roles/monitoring.metricWriter` (write-only) and binds the<br/>gateway's in-cluster ServiceAccount to it via Workload Identity. | `bool` | `false` | no |
| <a name="input_google_cloud_metrics_min_importance"></a> [google\_cloud\_metrics\_min\_importance](#input\_google\_cloud\_metrics\_min\_importance) | Metric tier to export: `essential`, `recommended`, `extended`, `diagnostic`, or `all`. Each tier includes the ones below it. A cost control — Cloud Monitoring bills per custom metric. | `string` | `"recommended"` | no |
| <a name="input_google_cloud_metrics_prefix"></a> [google\_cloud\_metrics\_prefix](#input\_google\_cloud\_metrics\_prefix) | Metric name prefix in Cloud Monitoring. Null uses the chart's default (`workload.googleapis.com/mzmon`). | `string` | `null` | no |
| <a name="input_grafana_admin_password"></a> [grafana\_admin\_password](#input\_grafana\_admin\_password) | Grafana admin password. Generated when null. | `string` | `null` | no |
| <a name="input_install_metrics_server"></a> [install\_metrics\_server](#input\_install\_metrics\_server) | Install metrics-server as part of the monitoring stack. Set true when the operator module has `install_metrics_server = false`, or the Materialize Console loses cluster metrics. | `bool` | `false` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels applied to the buckets this module creates. | `map(string)` | `{}` | no |
| <a name="input_logs_retention_days"></a> [logs\_retention\_days](#input\_logs\_retention\_days) | Delete Loki objects after this many days. Null disables the lifecycle rule and leaves retention to Loki's compactor. | `number` | `null` | no |
| <a name="input_materialize_instance_namespace"></a> [materialize\_instance\_namespace](#input\_materialize\_instance\_namespace) | Namespace the Materialize instance runs in. | `string` | `"materialize-environment"` | no |
| <a name="input_materialize_operator_namespace"></a> [materialize\_operator\_namespace](#input\_materialize\_operator\_namespace) | Namespace the Materialize operator runs in. | `string` | `"materialize"` | no |
| <a name="input_metrics_retention_days"></a> [metrics\_retention\_days](#input\_metrics\_retention\_days) | Delete Thanos objects after this many days. Null disables the lifecycle rule.<br/><br/>Leave it null unless you know what you are doing: Thanos's compactor already enforces<br/>retention per downsampling resolution (raw / 5m / 1h), and a bucket rule that deletes<br/>sooner removes blocks the compactor still expects to find. | `number` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace the monitoring stack is installed into. Also the namespace half of every Workload Identity member. | `string` | `"monitoring"` | no |
| <a name="input_node_selector"></a> [node\_selector](#input\_node\_selector) | Node selector for the centralized monitoring workloads. Not applied to the Alloy agent DaemonSet, which must reach every node. | `map(string)` | `{}` | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefix for the bucket and service-account names this module creates. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | GCP project holding the buckets and service accounts. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | Location for the telemetry buckets. | `string` | n/a | yes |
| <a name="input_sizing"></a> [sizing](#input\_sizing) | Deployment size: small, medium, or large. The chart's defaults are medium. | `string` | `"medium"` | no |
| <a name="input_storage_class"></a> [storage\_class](#input\_storage\_class) | StorageClass for the PVC-backed monitoring workloads (Alertmanager, the Loki ruler, and Thanos<br/>receive/compactor/store-gateway). Null uses the cluster default.<br/><br/>Must be a Hyperdisk class on C4/C4A/N4, which take only Hyperdisk — every default GKE class is<br/>Persistent Disk and fails to attach there. The examples create one and pass it here. | `string` | `null` | no |
| <a name="input_tolerations"></a> [tolerations](#input\_tolerations) | Tolerations for the monitoring workloads, including the Alloy agent DaemonSet. | <pre>list(object({<br/>    key      = optional(string)<br/>    operator = optional(string, "Equal")<br/>    value    = optional(string)<br/>    effect   = optional(string)<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_grafana_admin_password"></a> [grafana\_admin\_password](#output\_grafana\_admin\_password) | Grafana admin password. |
| <a name="output_grafana_url"></a> [grafana\_url](#output\_grafana\_url) | In-cluster URL for Grafana. Grafana is ClusterIP-only today, so reaching it means a port-forward. |
| <a name="output_logs_bucket"></a> [logs\_bucket](#output\_logs\_bucket) | GCS bucket holding Loki chunks and the ruler's state. |
| <a name="output_logs_url"></a> [logs\_url](#output\_logs\_url) | Loki read endpoint. |
| <a name="output_metrics_bucket"></a> [metrics\_bucket](#output\_metrics\_bucket) | GCS bucket holding Thanos blocks. |
| <a name="output_metrics_url"></a> [metrics\_url](#output\_metrics\_url) | Thanos Query endpoint. Prometheus-API-compatible. |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace the monitoring stack is installed into. |
| <a name="output_service_account_emails"></a> [service\_account\_emails](#output\_service\_account\_emails) | Google service account emails, by backend. |
| <a name="output_workload_identity_subjects"></a> [workload\_identity\_subjects](#output\_workload\_identity\_subjects) | Kubernetes service-account subjects the Workload Identity bindings are scoped to. Emitted by the monitoring module from the names the chart actually renders, so a mismatch with the bindings above is visible rather than silent. |
