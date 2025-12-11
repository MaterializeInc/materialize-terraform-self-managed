## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_azuread"></a> [azuread](#requirement\_azuread) | >= 2.45.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 3.75.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 2.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 2.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 3.75.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | ~> 2.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_network_security_group.aks](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_group) | resource |
| [azurerm_network_security_rule.public_lb_ingress](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_rule) | resource |
| [azurerm_subnet_network_security_group_association.subnet_sg_association](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_network_security_group_association) | resource |
| [kubernetes_service.balancerd_load_balancer](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service) | resource |
| [kubernetes_service.console_load_balancer](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aks_subnet_id"></a> [aks\_subnet\_id](#input\_aks\_subnet\_id) | The ID of the AKS subnet. | `string` | n/a | yes |
| <a name="input_ingress_cidr_blocks"></a> [ingress\_cidr\_blocks](#input\_ingress\_cidr\_blocks) | CIDR blocks that are allowed to reach the Azure LoadBalancers. | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_instance_name"></a> [instance\_name](#input\_instance\_name) | The name of the Materialize instance. | `string` | n/a | yes |
| <a name="input_internal"></a> [internal](#input\_internal) | Whether the load balancer is internal to the VNet. Defaults to false (public) to allow external access to Materialize. Set to true for VNet-only access. | `bool` | `false` | no |
| <a name="input_location"></a> [location](#input\_location) | The location of the resource group. | `string` | n/a | yes |
| <a name="input_materialize_balancerd_https_port"></a> [materialize\_balancerd\_https\_port](#input\_materialize\_balancerd\_https\_port) | HTTPS port configuration for Materialize balancerd service | `number` | `6876` | no |
| <a name="input_materialize_balancerd_sql_port"></a> [materialize\_balancerd\_sql\_port](#input\_materialize\_balancerd\_sql\_port) | SQL port configuration for Materialize balancerd service | `number` | `6875` | no |
| <a name="input_materialize_console_port"></a> [materialize\_console\_port](#input\_materialize\_console\_port) | Port configuration for Materialize console service | `number` | `8080` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | The kubernetes namespace to create the LoadBalancer Service in. | `string` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | The prefix for the resource group. | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | The name of the resource group. | `string` | n/a | yes |
| <a name="input_resource_id"></a> [resource\_id](#input\_resource\_id) | The resource\_id in the Materialize status. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | The tags for the resource group. | `map(string)` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_balancerd_load_balancer_ip"></a> [balancerd\_load\_balancer\_ip](#output\_balancerd\_load\_balancer\_ip) | IP address of load balancer pointing at balancerd. |
| <a name="output_console_load_balancer_ip"></a> [console\_load\_balancer\_ip](#output\_console\_load\_balancer\_ip) | IP address of load balancer pointing at the web console. |
| <a name="output_instance_name"></a> [instance\_name](#output\_instance\_name) | The name of the Materialize instance. |
| <a name="output_network_security_group_id"></a> [network\_security\_group\_id](#output\_network\_security\_group\_id) | The ID of the network security group. |
| <a name="output_network_security_group_name"></a> [network\_security\_group\_name](#output\_network\_security\_group\_name) | The name of the network security group. |
