## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0, < 5.101.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 2.5.0, < 2.18.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.10.0, < 2.39.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.0.0, < 3.10.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 5.0, < 5.101.0 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.0.0, < 3.10.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_monitoring"></a> [monitoring](#module\_monitoring) | github.com/MaterializeInc/materialize-monitoring//terraform/modules/materialize-monitoring | materialize-monitoring/v0.12.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_role.telemetry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.telemetry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_s3_bucket.telemetry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.telemetry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_public_access_block.telemetry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.telemetry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.telemetry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [random_id.bucket_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |
| [aws_iam_policy_document.assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.bucket_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_additional_values"></a> [additional\_values](#input\_additional\_values) | Raw YAML documents appended to the Helm values, last, so they override everything the modules compute. | `list(string)` | `[]` | no |
| <a name="input_bucket_force_destroy"></a> [bucket\_force\_destroy](#input\_bucket\_force\_destroy) | Allow Terraform to delete non-empty buckets. Leave false outside throwaway environments — destroying it takes the telemetry with it. | `bool` | `false` | no |
| <a name="input_chart_registry"></a> [chart\_registry](#input\_chart\_registry) | OCI registry holding the materialize-monitoring charts. Override for a mirrored or air-gapped registry; there is no way to reach this through `additional_values`. | `string` | `null` | no |
| <a name="input_chart_version"></a> [chart\_version](#input\_chart\_version) | Override the materialize-monitoring chart version. Leave null to use the version the pinned module ships with — the two are one release. | `string` | `null` | no |
| <a name="input_cluster_oidc_issuer_url"></a> [cluster\_oidc\_issuer\_url](#input\_cluster\_oidc\_issuer\_url) | OIDC issuer URL of the cluster, from the EKS module. | `string` | n/a | yes |
| <a name="input_create_namespace"></a> [create\_namespace](#input\_create\_namespace) | Whether the monitoring module creates the namespace. False by default because the operator module already creates `monitoring`. | `bool` | `false` | no |
| <a name="input_enable_bucket_versioning"></a> [enable\_bucket\_versioning](#input\_enable\_bucket\_versioning) | Enable versioning on the telemetry buckets. Versioning is the disaster-recovery primitive for both Loki and Thanos, neither of which has a native snapshot. | `bool` | `true` | no |
| <a name="input_enable_monitoring_crds"></a> [enable\_monitoring\_crds](#input\_enable\_monitoring\_crds) | Install the materialize-monitoring-crds chart (prometheus-operator and grafana-operator CRDs). Set false when the cluster already has them from elsewhere, such as kube-prometheus-stack or a platform team that owns CRDs centrally. Null uses the monitoring module's default. | `bool` | `null` | no |
| <a name="input_grafana_admin_password"></a> [grafana\_admin\_password](#input\_grafana\_admin\_password) | Grafana admin password. Generated when null. | `string` | `null` | no |
| <a name="input_iam_permissions_boundary"></a> [iam\_permissions\_boundary](#input\_iam\_permissions\_boundary) | Optional permissions boundary applied to the IAM roles this module creates. | `string` | `null` | no |
| <a name="input_install_metrics_server"></a> [install\_metrics\_server](#input\_install\_metrics\_server) | Install metrics-server as part of the monitoring stack. Set true when the operator module has `install_metrics_server = false`, or the Materialize Console loses cluster metrics. | `bool` | `false` | no |
| <a name="input_install_timeout"></a> [install\_timeout](#input\_install\_timeout) | Timeout for each Helm release, in seconds. Null uses the monitoring module's default, which is well above Helm's 300s because a first install brings up Loki, Thanos, Grafana, and both Alloy roles together. | `number` | `null` | no |
| <a name="input_logs_retention_days"></a> [logs\_retention\_days](#input\_logs\_retention\_days) | Expire Loki objects after this many days. Null disables the lifecycle rule and leaves retention entirely to Loki's compactor. | `number` | `null` | no |
| <a name="input_materialize_instance_namespace"></a> [materialize\_instance\_namespace](#input\_materialize\_instance\_namespace) | Namespace the Materialize instance runs in. | `string` | `"materialize-environment"` | no |
| <a name="input_materialize_operator_namespace"></a> [materialize\_operator\_namespace](#input\_materialize\_operator\_namespace) | Namespace the Materialize operator runs in. | `string` | `"materialize"` | no |
| <a name="input_metrics_retention_days"></a> [metrics\_retention\_days](#input\_metrics\_retention\_days) | Expire Thanos objects after this many days. Null disables the lifecycle rule.<br/><br/>Leave it null unless you know what you are doing: Thanos's compactor already enforces<br/>retention per downsampling resolution (raw / 5m / 1h), and a bucket rule that expires<br/>sooner deletes blocks the compactor still expects to find. | `number` | `null` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix for the bucket and IAM role names this module creates. Capped at 40 characters so the longest generated name still fits: S3 bucket names are limited to 63, and `-mzmon-metrics-` plus the 8-character random suffix takes 23. | `string` | n/a | yes |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace the monitoring stack is installed into. Also the namespace half of every IRSA trust-policy subject. | `string` | `"monitoring"` | no |
| <a name="input_node_selector"></a> [node\_selector](#input\_node\_selector) | Node selector for the centralized monitoring workloads. Not applied to the Alloy agent DaemonSet, which must reach every node. | `map(string)` | `{}` | no |
| <a name="input_oidc_provider_arn"></a> [oidc\_provider\_arn](#input\_oidc\_provider\_arn) | ARN of the cluster's IAM OIDC provider, from the EKS module. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region the buckets live in. Passed explicitly rather than read from a data source, matching the rest of this repository. | `string` | n/a | yes |
| <a name="input_sizing"></a> [sizing](#input\_sizing) | Deployment size: small, medium, or large. The chart's defaults are medium. | `string` | `"medium"` | no |
| <a name="input_storage_class"></a> [storage\_class](#input\_storage\_class) | StorageClass for the PVC-backed monitoring workloads (Alertmanager, the Loki ruler, and Thanos receive/compactor/store-gateway). Null uses whatever class the cluster marks default; the examples pass the `gp3` class from the `ebs-csi-driver` module. | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the resources this module creates. | `map(string)` | `{}` | no |
| <a name="input_tolerations"></a> [tolerations](#input\_tolerations) | Tolerations for the monitoring workloads, including the Alloy agent DaemonSet. | <pre>list(object({<br/>    key      = optional(string)<br/>    operator = optional(string, "Equal")<br/>    value    = optional(string)<br/>    effect   = optional(string)<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_grafana_admin_password"></a> [grafana\_admin\_password](#output\_grafana\_admin\_password) | Grafana admin password. |
| <a name="output_grafana_url"></a> [grafana\_url](#output\_grafana\_url) | In-cluster URL for Grafana. Grafana is ClusterIP-only today, so reaching it means a port-forward. |
| <a name="output_iam_role_arns"></a> [iam\_role\_arns](#output\_iam\_role\_arns) | IRSA role ARNs, by backend. |
| <a name="output_logs_bucket"></a> [logs\_bucket](#output\_logs\_bucket) | S3 bucket holding Loki chunks and the ruler's state. |
| <a name="output_logs_url"></a> [logs\_url](#output\_logs\_url) | Loki read endpoint. |
| <a name="output_metrics_bucket"></a> [metrics\_bucket](#output\_metrics\_bucket) | S3 bucket holding Thanos blocks. |
| <a name="output_metrics_url"></a> [metrics\_url](#output\_metrics\_url) | Thanos Query endpoint. Prometheus-API-compatible. |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace the monitoring stack is installed into. |
| <a name="output_workload_identity_subjects"></a> [workload\_identity\_subjects](#output\_workload\_identity\_subjects) | Service-account subjects the IRSA trust policies are scoped to. Emitted by the monitoring module from the names the chart actually renders, so a mismatch with the roles above is visible rather than silent. |
