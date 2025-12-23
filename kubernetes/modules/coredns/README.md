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
| <a name="provider_null"></a> [null](#provider\_null) | ~> 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [kubernetes_cluster_role.coredns](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/cluster_role) | resource |
| [kubernetes_cluster_role_binding.coredns](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/cluster_role_binding) | resource |
| [kubernetes_config_map.coredns](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/config_map) | resource |
| [kubernetes_deployment.coredns](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/deployment) | resource |
| [kubernetes_service_account.coredns](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service_account) | resource |
| [null_resource.scale_down_kube_dns](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [null_resource.scale_down_kube_dns_autoscaler](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |

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
| <a name="input_memory_limit"></a> [memory\_limit](#input\_memory\_limit) | Memory limit for CoreDNS container | `string` | `"170Mi"` | no |
| <a name="input_memory_request"></a> [memory\_request](#input\_memory\_request) | Memory request for CoreDNS container | `string` | `"70Mi"` | no |
| <a name="input_node_selector"></a> [node\_selector](#input\_node\_selector) | Node selector for CoreDNS deployment | `map(string)` | `{}` | no |
| <a name="input_replicas"></a> [replicas](#input\_replicas) | Number of CoreDNS replicas | `number` | `2` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_config_map_name"></a> [config\_map\_name](#output\_config\_map\_name) | Name of the CoreDNS ConfigMap |
| <a name="output_deployment_name"></a> [deployment\_name](#output\_deployment\_name) | Name of the custom CoreDNS deployment |
| <a name="output_service_account_name"></a> [service\_account\_name](#output\_service\_account\_name) | Name of the CoreDNS service account |
