## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 2.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 2.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_helm"></a> [helm](#provider\_helm) | ~> 2.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | ~> 2.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [helm_release.materialize_operator](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.metrics_server](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_namespace.materialize](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace) | resource |
| [kubernetes_namespace.monitoring](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aws_account_id"></a> [aws\_account\_id](#input\_aws\_account\_id) | AWS account ID for the operator Helm values. | `string` | n/a | yes |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region for the operator Helm values. | `string` | n/a | yes |
| <a name="input_enable_license_key_checks"></a> [enable\_license\_key\_checks](#input\_enable\_license\_key\_checks) | Enable license key checks. | `bool` | `true` | no |
| <a name="input_helm_chart"></a> [helm\_chart](#input\_helm\_chart) | Chart name from repository or local path to chart. For local charts, set the path to the chart directory. | `string` | `"materialize-operator"` | no |
| <a name="input_helm_repository"></a> [helm\_repository](#input\_helm\_repository) | Repository URL for the Materialize operator Helm chart. Leave empty if using local chart. | `string` | `"https://materializeinc.github.io/materialize/"` | no |
| <a name="input_helm_values"></a> [helm\_values](#input\_helm\_values) | Values to pass to the Helm chart | `any` | `{}` | no |
| <a name="input_install_metrics_server"></a> [install\_metrics\_server](#input\_install\_metrics\_server) | Whether to install the metrics-server | `bool` | `true` | no |
| <a name="input_metrics_server_values"></a> [metrics\_server\_values](#input\_metrics\_server\_values) | Configuration values for metrics-server | <pre>object({<br/>    metrics_enabled       = string<br/>    skip_tls_verification = bool<br/>  })</pre> | <pre>{<br/>  "metrics_enabled": "true",<br/>  "skip_tls_verification": true<br/>}</pre> | no |
| <a name="input_metrics_server_version"></a> [metrics\_server\_version](#input\_metrics\_server\_version) | Version of metrics-server to install | `string` | `"3.12.2"` | no |
| <a name="input_monitoring_namespace"></a> [monitoring\_namespace](#input\_monitoring\_namespace) | Namespace for monitoring resources | `string` | `"monitoring"` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix for all resource names (replaces separate namespace and environment variables) | `string` | n/a | yes |
| <a name="input_operator_namespace"></a> [operator\_namespace](#input\_operator\_namespace) | Namespace for the Materialize operator | `string` | `"materialize"` | no |
| <a name="input_operator_version"></a> [operator\_version](#input\_operator\_version) | Version of the Materialize operator to install | `string` | `"v25.3.0-beta.1"` | no |
| <a name="input_orchestratord_version"></a> [orchestratord\_version](#input\_orchestratord\_version) | Version of the Materialize orchestrator to install | `string` | `null` | no |
| <a name="input_swap_enabled"></a> [swap\_enabled](#input\_swap\_enabled) | Whether to enable swap on the local NVMe disks. | `bool` | `true` | no |
| <a name="input_use_local_chart"></a> [use\_local\_chart](#input\_use\_local\_chart) | Whether to use a local chart instead of one from a repository | `bool` | `false` | no |
| <a name="input_use_self_signed_cluster_issuer"></a> [use\_self\_signed\_cluster\_issuer](#input\_use\_self\_signed\_cluster\_issuer) | Whether to use a self-signed cluster issuer for cert-manager. | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_operator_namespace"></a> [operator\_namespace](#output\_operator\_namespace) | Namespace where the operator is installed |
| <a name="output_operator_release_name"></a> [operator\_release\_name](#output\_operator\_release\_name) | Helm release name of the operator |
| <a name="output_operator_release_status"></a> [operator\_release\_status](#output\_operator\_release\_status) | Status of the helm release |
