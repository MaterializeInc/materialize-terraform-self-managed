## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 2.5.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.10.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_helm"></a> [helm](#provider\_helm) | >= 2.5.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | >= 2.10.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [helm_release.metrics_server](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_namespace.metrics_server](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_chart_version"></a> [chart\_version](#input\_chart\_version) | Version of the metrics-server Helm chart | `string` | `"3.12.2"` | no |
| <a name="input_create_namespace"></a> [create\_namespace](#input\_create\_namespace) | Whether to create the namespace | `bool` | `true` | no |
| <a name="input_metrics_enabled"></a> [metrics\_enabled](#input\_metrics\_enabled) | Whether to enable metrics collection | `bool` | `true` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Kubernetes namespace for metrics-server | `string` | `"monitoring"` | no |
| <a name="input_node_selector"></a> [node\_selector](#input\_node\_selector) | Node selector for metrics-server pods | `map(string)` | `{}` | no |
| <a name="input_release_name"></a> [release\_name](#input\_release\_name) | Name for the Helm release | `string` | `"metrics-server"` | no |
| <a name="input_skip_tls_verification"></a> [skip\_tls\_verification](#input\_skip\_tls\_verification) | Whether to skip TLS verification when connecting to kubelets | `bool` | `true` | no |
| <a name="input_tolerations"></a> [tolerations](#input\_tolerations) | Tolerations for metrics-server pods | <pre>list(object({<br/>    key      = string<br/>    value    = optional(string)<br/>    operator = optional(string, "Equal")<br/>    effect   = string<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace where metrics-server is deployed |
| <a name="output_release_name"></a> [release\_name](#output\_release\_name) | Name of the metrics-server Helm release |
