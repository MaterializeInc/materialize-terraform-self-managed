## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 4.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.5 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | ~> 4.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_kubernetes_cluster.aks](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster) | resource |
| [azurerm_role_assignment.aks_network_contributer](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_user_assigned_identity.aks_identity](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [azurerm_user_assigned_identity.workload_identity](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [azurerm_subscription.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/subscription) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_azure_ad_admin_group_object_ids"></a> [azure\_ad\_admin\_group\_object\_ids](#input\_azure\_ad\_admin\_group\_object\_ids) | List of Azure AD group object IDs that will have admin access to the cluster, applied only if enable\_azure\_ad\_rbac is true | `list(string)` | `[]` | no |
| <a name="input_default_node_pool_enable_auto_scaling"></a> [default\_node\_pool\_enable\_auto\_scaling](#input\_default\_node\_pool\_enable\_auto\_scaling) | Enable auto scaling for the default node pool | `bool` | `true` | no |
| <a name="input_default_node_pool_max_count"></a> [default\_node\_pool\_max\_count](#input\_default\_node\_pool\_max\_count) | Maximum number of nodes in the default node pool (used only when auto scaling is enabled) | `number` | `5` | no |
| <a name="input_default_node_pool_min_count"></a> [default\_node\_pool\_min\_count](#input\_default\_node\_pool\_min\_count) | Minimum number of nodes in the default node pool (used only when auto scaling is enabled) | `number` | `1` | no |
| <a name="input_default_node_pool_node_count"></a> [default\_node\_pool\_node\_count](#input\_default\_node\_pool\_node\_count) | Number of nodes in the default node pool (used only when auto scaling is disabled) | `number` | `1` | no |
| <a name="input_default_node_pool_node_labels"></a> [default\_node\_pool\_node\_labels](#input\_default\_node\_pool\_node\_labels) | Node labels for the default node pool | `map(string)` | `{}` | no |
| <a name="input_default_node_pool_os_disk_size_gb"></a> [default\_node\_pool\_os\_disk\_size\_gb](#input\_default\_node\_pool\_os\_disk\_size\_gb) | OS disk size in GB for the default node pool | `number` | `100` | no |
| <a name="input_default_node_pool_vm_size"></a> [default\_node\_pool\_vm\_size](#input\_default\_node\_pool\_vm\_size) | VM size for the default node pool (system node pool) | `string` | `"Standard_D2s_v3"` | no |
| <a name="input_dns_service_ip"></a> [dns\_service\_ip](#input\_dns\_service\_ip) | IP address within the service CIDR that will be used by cluster service discovery (kube-dns). If not specified, will be calculated automatically. | `string` | `null` | no |
| <a name="input_enable_azure_ad_rbac"></a> [enable\_azure\_ad\_rbac](#input\_enable\_azure\_ad\_rbac) | Enable Azure Active Directory integration for RBAC | `bool` | `false` | no |
| <a name="input_enable_azure_monitor"></a> [enable\_azure\_monitor](#input\_enable\_azure\_monitor) | Enable Azure Monitor for the AKS cluster | `bool` | `false` | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | Version of Kubernetes to use for the AKS cluster | `string` | `"1.32"` | no |
| <a name="input_load_balancer_sku"></a> [load\_balancer\_sku](#input\_load\_balancer\_sku) | SKU of the Load Balancer used for this Kubernetes Cluster | `string` | `"standard"` | no |
| <a name="input_location"></a> [location](#input\_location) | The location where resources will be created | `string` | n/a | yes |
| <a name="input_log_analytics_workspace_id"></a> [log\_analytics\_workspace\_id](#input\_log\_analytics\_workspace\_id) | Log Analytics workspace ID for Azure Monitor (required if enable\_azure\_monitor is true) | `string` | `null` | no |
| <a name="input_network_data_plane"></a> [network\_data\_plane](#input\_network\_data\_plane) | Network data plane to use (azure or cilium). When using cilium network policy, this must be set to cilium. | `string` | `"cilium"` | no |
| <a name="input_network_plugin"></a> [network\_plugin](#input\_network\_plugin) | Network plugin to use (azure or kubenet) | `string` | `"azure"` | no |
| <a name="input_network_policy"></a> [network\_policy](#input\_network\_policy) | Network policy to use (azure, calico, cilium, or null). Note: Azure Network Policy Manager is deprecated; migrate to cilium by 2028. | `string` | `"cilium"` | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefix to be used for resource names | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | The name of the resource group | `string` | n/a | yes |
| <a name="input_service_cidr"></a> [service\_cidr](#input\_service\_cidr) | CIDR range for Kubernetes services | `string` | n/a | yes |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | The ID of the subnet for AKS | `string` | n/a | yes |
| <a name="input_subnet_name"></a> [subnet\_name](#input\_subnet\_name) | The name of the subnet for AKS | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to resources | `map(string)` | `{}` | no |
| <a name="input_vnet_name"></a> [vnet\_name](#input\_vnet\_name) | The name of the virtual network. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | The endpoint of the AKS cluster |
| <a name="output_cluster_fqdn"></a> [cluster\_fqdn](#output\_cluster\_fqdn) | The FQDN of the AKS cluster |
| <a name="output_cluster_id"></a> [cluster\_id](#output\_cluster\_id) | The ID of the AKS cluster |
| <a name="output_cluster_identity_client_id"></a> [cluster\_identity\_client\_id](#output\_cluster\_identity\_client\_id) | The client ID of the AKS cluster identity |
| <a name="output_cluster_identity_id"></a> [cluster\_identity\_id](#output\_cluster\_identity\_id) | The ID of the AKS cluster identity |
| <a name="output_cluster_identity_principal_id"></a> [cluster\_identity\_principal\_id](#output\_cluster\_identity\_principal\_id) | The principal ID of the AKS cluster identity |
| <a name="output_cluster_kubernetes_version"></a> [cluster\_kubernetes\_version](#output\_cluster\_kubernetes\_version) | The version of Kubernetes used by the AKS cluster |
| <a name="output_cluster_location"></a> [cluster\_location](#output\_cluster\_location) | The location of the AKS cluster |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | The name of the AKS cluster |
| <a name="output_cluster_node_resource_group"></a> [cluster\_node\_resource\_group](#output\_cluster\_node\_resource\_group) | The resource group containing the AKS cluster nodes |
| <a name="output_cluster_oidc_issuer_url"></a> [cluster\_oidc\_issuer\_url](#output\_cluster\_oidc\_issuer\_url) | The OIDC issuer URL of the AKS cluster |
| <a name="output_cluster_portal_fqdn"></a> [cluster\_portal\_fqdn](#output\_cluster\_portal\_fqdn) | The portal FQDN of the AKS cluster |
| <a name="output_cluster_private_fqdn"></a> [cluster\_private\_fqdn](#output\_cluster\_private\_fqdn) | The private FQDN of the AKS cluster |
| <a name="output_cluster_resource_group_name"></a> [cluster\_resource\_group\_name](#output\_cluster\_resource\_group\_name) | The resource group name of the AKS cluster |
| <a name="output_kube_config"></a> [kube\_config](#output\_kube\_config) | The kube\_config for the AKS cluster |
| <a name="output_kube_config_raw"></a> [kube\_config\_raw](#output\_kube\_config\_raw) | The raw kube\_config for the AKS cluster |
| <a name="output_workload_identity_client_id"></a> [workload\_identity\_client\_id](#output\_workload\_identity\_client\_id) | The client ID of the workload identity |
| <a name="output_workload_identity_id"></a> [workload\_identity\_id](#output\_workload\_identity\_id) | The ID of the workload identity |
| <a name="output_workload_identity_principal_id"></a> [workload\_identity\_principal\_id](#output\_workload\_identity\_principal\_id) | The principal ID of the workload identity |
