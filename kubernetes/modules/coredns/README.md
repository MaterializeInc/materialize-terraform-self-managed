## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.8 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 2.0 |
| <a name="requirement_null"></a> [null](#requirement\_null) | ~> 3.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | ~> 2.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_hpa"></a> [hpa](#module\_hpa) | ../hpa | n/a |

## Resources

| Name | Type |
|------|------|
| [kubernetes_cluster_role.coredns](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/cluster_role) | resource |
| [kubernetes_cluster_role_binding.coredns](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/cluster_role_binding) | resource |
| [kubernetes_config_map.coredns](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/config_map) | resource |
| [kubernetes_deployment.coredns](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/deployment) | resource |
| [kubernetes_service_account.coredns](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service_account) | resource |
| [terraform_data.scale_down_kube_dns](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.scale_down_kube_dns_autoscaler](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.scale_up_kube_dns](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.scale_up_kube_dns_autoscaler](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_coredns_autoscaler_deployment_to_scale_down"></a> [coredns\_autoscaler\_deployment\_to\_scale\_down](#input\_coredns\_autoscaler\_deployment\_to\_scale\_down) | Name of the CoreDNS autoscaler deployment to scale down | `string` | `"coredns-autoscaler"` | no |
| <a name="input_coredns_deployment_to_scale_down"></a> [coredns\_deployment\_to\_scale\_down](#input\_coredns\_deployment\_to\_scale\_down) | Name of the CoreDNS deployment to scale down | `string` | `"coredns"` | no |
| <a name="input_coredns_version"></a> [coredns\_version](#input\_coredns\_version) | CoreDNS image version | `string` | `"1.11.1"` | no |
| <a name="input_cpu_request"></a> [cpu\_request](#input\_cpu\_request) | CPU request for CoreDNS container | `string` | `"100m"` | no |
| <a name="input_create_coredns_service_account"></a> [create\_coredns\_service\_account](#input\_create\_coredns\_service\_account) | Whether to create the CoreDNS service account | `bool` | `false` | no |
| <a name="input_disable_default_coredns"></a> [disable\_default\_coredns](#input\_disable\_default\_coredns) | Whether to scale down the default kube-dns deployment | `bool` | `true` | no |
| <a name="input_disable_default_coredns_autoscaler"></a> [disable\_default\_coredns\_autoscaler](#input\_disable\_default\_coredns\_autoscaler) | Whether to scale down the default kube-dns autoscaler deployment | `bool` | `true` | no |
| <a name="input_hpa_cpu_target_utilization"></a> [hpa\_cpu\_target\_utilization](#input\_hpa\_cpu\_target\_utilization) | Target CPU utilization percentage for HPA | `number` | `60` | no |
| <a name="input_hpa_max_replicas"></a> [hpa\_max\_replicas](#input\_hpa\_max\_replicas) | Maximum number of replicas for HPA | `number` | `100` | no |
| <a name="input_hpa_memory_target_utilization"></a> [hpa\_memory\_target\_utilization](#input\_hpa\_memory\_target\_utilization) | Target memory utilization percentage for HPA | `number` | `50` | no |
| <a name="input_hpa_min_replicas"></a> [hpa\_min\_replicas](#input\_hpa\_min\_replicas) | Minimum number of replicas for HPA | `number` | `2` | no |
| <a name="input_hpa_policy_period_seconds"></a> [hpa\_policy\_period\_seconds](#input\_hpa\_policy\_period\_seconds) | Period in seconds for scaling policies | `number` | `15` | no |
| <a name="input_hpa_scale_down_percent_per_period"></a> [hpa\_scale\_down\_percent\_per\_period](#input\_hpa\_scale\_down\_percent\_per\_period) | Maximum percent to scale down per period | `number` | `100` | no |
| <a name="input_hpa_scale_down_stabilization_window"></a> [hpa\_scale\_down\_stabilization\_window](#input\_hpa\_scale\_down\_stabilization\_window) | Stabilization window for scale down in seconds | `number` | `600` | no |
| <a name="input_hpa_scale_up_percent_per_period"></a> [hpa\_scale\_up\_percent\_per\_period](#input\_hpa\_scale\_up\_percent\_per\_period) | Maximum percent to scale up per period | `number` | `100` | no |
| <a name="input_hpa_scale_up_pods_per_period"></a> [hpa\_scale\_up\_pods\_per\_period](#input\_hpa\_scale\_up\_pods\_per\_period) | Maximum pods to add per period during scale up | `number` | `4` | no |
| <a name="input_hpa_scale_up_stabilization_window"></a> [hpa\_scale\_up\_stabilization\_window](#input\_hpa\_scale\_up\_stabilization\_window) | Stabilization window for scale up in seconds | `number` | `180` | no |
| <a name="input_kubeconfig_data"></a> [kubeconfig\_data](#input\_kubeconfig\_data) | Kubeconfig data for kubectl commands | `string` | n/a | yes |
| <a name="input_memory_limit"></a> [memory\_limit](#input\_memory\_limit) | Memory limit for CoreDNS container | `string` | `"170Mi"` | no |
| <a name="input_memory_request"></a> [memory\_request](#input\_memory\_request) | Memory request for CoreDNS container | `string` | `"170Mi"` | no |
| <a name="input_node_selector"></a> [node\_selector](#input\_node\_selector) | Node selector for CoreDNS deployment | `map(string)` | `{}` | no |
| <a name="input_replicas"></a> [replicas](#input\_replicas) | Number of CoreDNS replicas | `number` | `2` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_config_map_name"></a> [config\_map\_name](#output\_config\_map\_name) | Name of the CoreDNS ConfigMap |
| <a name="output_deployment_name"></a> [deployment\_name](#output\_deployment\_name) | Name of the custom CoreDNS deployment |
| <a name="output_service_account_name"></a> [service\_account\_name](#output\_service\_account\_name) | Name of the CoreDNS service account |
