## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 2.5.0 |
| <a name="requirement_http"></a> [http](#requirement\_http) | >= 3.0.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.10.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_helm"></a> [helm](#provider\_helm) | >= 2.5.0 |
| <a name="provider_http"></a> [http](#provider\_http) | >= 3.0.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | >= 2.10.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [helm_release.prometheus](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_namespace.prometheus](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace) | resource |
| [http_http.scrape_config](https://registry.terraform.io/providers/hashicorp/http/latest/docs/data-sources/http) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_chart_version"></a> [chart\_version](#input\_chart\_version) | Version of the Prometheus helm chart | `string` | `"28.0.0"` | no |
| <a name="input_create_namespace"></a> [create\_namespace](#input\_create\_namespace) | Whether to create the namespace | `bool` | `true` | no |
| <a name="input_install_timeout"></a> [install\_timeout](#input\_install\_timeout) | Timeout for installing the Prometheus helm chart, in seconds | `number` | `600` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Kubernetes namespace for Prometheus | `string` | `"monitoring"` | no |
| <a name="input_node_selector"></a> [node\_selector](#input\_node\_selector) | Node selector for Prometheus pods | `map(string)` | `{}` | no |
| <a name="input_retention_days"></a> [retention\_days](#input\_retention\_days) | Number of days to retain Prometheus data | `number` | `15` | no |
| <a name="input_server_resources"></a> [server\_resources](#input\_server\_resources) | Resource requests and limits for Prometheus server | <pre>object({<br/>    requests = optional(object({<br/>      cpu    = optional(string, "500m")<br/>      memory = optional(string, "512Mi")<br/>    }))<br/>    limits = optional(object({<br/>      cpu    = optional(string, "1000m")<br/>      memory = optional(string, "1Gi")<br/>    }))<br/>  })</pre> | <pre>{<br/>  "limits": {},<br/>  "requests": {}<br/>}</pre> | no |
| <a name="input_storage_class"></a> [storage\_class](#input\_storage\_class) | Storage class for Prometheus server persistent volume | `string` | n/a | yes |
| <a name="input_storage_size"></a> [storage\_size](#input\_storage\_size) | Storage size for Prometheus server persistent volume | `string` | `"50Gi"` | no |
| <a name="input_tolerations"></a> [tolerations](#input\_tolerations) | Tolerations for Prometheus pods | <pre>list(object({<br/>    key      = string<br/>    value    = optional(string)<br/>    operator = optional(string, "Equal")<br/>    effect   = string<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace where Prometheus is deployed |
| <a name="output_prometheus_url"></a> [prometheus\_url](#output\_prometheus\_url) | Internal URL for Prometheus server (for use as Grafana data source) |
| <a name="output_release_name"></a> [release\_name](#output\_release\_name) | Name of the Prometheus Helm release |
