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
| <a name="provider_random"></a> [random](#provider\_random) | ~> 3.5 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_virtual_network"></a> [virtual\_network](#module\_virtual\_network) | Azure/avm-res-network-virtualnetwork/azurerm | 0.10.0 |

## Resources

| Name | Type |
|------|------|
| [azurerm_nat_gateway.main](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/nat_gateway) | resource |
| [azurerm_nat_gateway_public_ip_association.main](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/nat_gateway_public_ip_association) | resource |
| [azurerm_private_dns_zone.postgres](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone) | resource |
| [azurerm_private_dns_zone_virtual_network_link.postgres](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone_virtual_network_link) | resource |
| [azurerm_public_ip.nat_gateway](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/public_ip) | resource |
| [random_id.dns_zone_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aks_subnet_cidr"></a> [aks\_subnet\_cidr](#input\_aks\_subnet\_cidr) | CIDR range for the AKS subnet | `string` | n/a | yes |
| <a name="input_api_server_subnet_cidr"></a> [api\_server\_subnet\_cidr](#input\_api\_server\_subnet\_cidr) | CIDR range for the API Server VNet Integration delegated subnet (minimum /28, recommended /27) | `string` | `null` | no |
| <a name="input_enable_api_server_vnet_integration"></a> [enable\_api\_server\_vnet\_integration](#input\_enable\_api\_server\_vnet\_integration) | Enable API Server VNet Integration (requires api\_server\_subnet\_cidr to be set) | `bool` | `false` | no |
| <a name="input_location"></a> [location](#input\_location) | The location where resources will be created | `string` | n/a | yes |
| <a name="input_nat_gateway_idle_timeout"></a> [nat\_gateway\_idle\_timeout](#input\_nat\_gateway\_idle\_timeout) | The idle timeout in minutes for the NAT Gateway | `number` | `4` | no |
| <a name="input_postgres_subnet_cidr"></a> [postgres\_subnet\_cidr](#input\_postgres\_subnet\_cidr) | CIDR range for the PostgreSQL subnet | `string` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefix to be used for resource names | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | The name of the resource group | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to resources | `map(string)` | `{}` | no |
| <a name="input_vnet_address_space"></a> [vnet\_address\_space](#input\_vnet\_address\_space) | Address space for the VNet | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_aks_subnet_id"></a> [aks\_subnet\_id](#output\_aks\_subnet\_id) | The ID of the AKS subnet |
| <a name="output_aks_subnet_name"></a> [aks\_subnet\_name](#output\_aks\_subnet\_name) | The name of the AKS subnet |
| <a name="output_api_server_subnet_id"></a> [api\_server\_subnet\_id](#output\_api\_server\_subnet\_id) | The ID of the API server subnet (null if VNet Integration is not enabled) |
| <a name="output_api_server_subnet_name"></a> [api\_server\_subnet\_name](#output\_api\_server\_subnet\_name) | The name of the API server subnet (null if VNet Integration is not enabled) |
| <a name="output_nat_gateway_id"></a> [nat\_gateway\_id](#output\_nat\_gateway\_id) | The ID of the NAT Gateway |
| <a name="output_nat_gateway_public_ip"></a> [nat\_gateway\_public\_ip](#output\_nat\_gateway\_public\_ip) | The public IP address of the NAT Gateway |
| <a name="output_postgres_subnet_id"></a> [postgres\_subnet\_id](#output\_postgres\_subnet\_id) | The ID of the PostgreSQL subnet |
| <a name="output_private_dns_zone_id"></a> [private\_dns\_zone\_id](#output\_private\_dns\_zone\_id) | The ID of the private DNS zone |
| <a name="output_vnet_address_space"></a> [vnet\_address\_space](#output\_vnet\_address\_space) | The address space of the VNet |
| <a name="output_vnet_id"></a> [vnet\_id](#output\_vnet\_id) | The ID of the VNet |
| <a name="output_vnet_name"></a> [vnet\_name](#output\_vnet\_name) | The name of the VNet |
