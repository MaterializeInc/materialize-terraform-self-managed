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
| [helm_release.grafana](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_config_map.dashboards](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/config_map) | resource |
| [kubernetes_namespace.grafana](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace) | resource |
| [http_http.dashboards](https://registry.terraform.io/providers/hashicorp/http/latest/docs/data-sources/http) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_admin_password"></a> [admin\_password](#input\_admin\_password) | Admin password for Grafana. If not set, a random password will be generated. | `string` | `null` | no |
| <a name="input_chart_version"></a> [chart\_version](#input\_chart\_version) | Version of the Grafana helm chart | `string` | `"10.5.0"` | no |
| <a name="input_create_namespace"></a> [create\_namespace](#input\_create\_namespace) | Whether to create the namespace | `bool` | `false` | no |
| <a name="input_install_timeout"></a> [install\_timeout](#input\_install\_timeout) | Timeout for installing the Grafana helm chart, in seconds | `number` | `600` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Kubernetes namespace for Grafana | `string` | `"monitoring"` | no |
| <a name="input_node_selector"></a> [node\_selector](#input\_node\_selector) | Node selector for Grafana pods | `map(string)` | `{}` | no |
| <a name="input_prometheus_url"></a> [prometheus\_url](#input\_prometheus\_url) | URL of the Prometheus server to use as data source | `string` | n/a | yes |
| <a name="input_resources"></a> [resources](#input\_resources) | Resource requests and limits for Grafana | <pre>object({<br/>    requests = optional(object({<br/>      cpu    = optional(string, "100m")<br/>      memory = optional(string, "128Mi")<br/>    }))<br/>    limits = optional(object({<br/>      cpu    = optional(string, "500m")<br/>      memory = optional(string, "512Mi")<br/>    }))<br/>  })</pre> | <pre>{<br/>  "limits": {},<br/>  "requests": {}<br/>}</pre> | no |
| <a name="input_storage_size"></a> [storage\_size](#input\_storage\_size) | Storage size for Grafana persistent volume | `string` | `"10Gi"` | no |
| <a name="input_tolerations"></a> [tolerations](#input\_tolerations) | Tolerations for Grafana pods | <pre>list(object({<br/>    key      = string<br/>    value    = optional(string)<br/>    operator = optional(string, "Equal")<br/>    effect   = string<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_admin_password"></a> [admin\_password](#output\_admin\_password) | Admin password for Grafana (retrieve with: kubectl get secret grafana -n monitoring -o jsonpath='{.data.admin-password}' \| base64 -d) |
| <a name="output_grafana_url"></a> [grafana\_url](#output\_grafana\_url) | Internal URL for Grafana |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace where Grafana is deployed |
| <a name="output_release_name"></a> [release\_name](#output\_release\_name) | Name of the Grafana Helm release |
