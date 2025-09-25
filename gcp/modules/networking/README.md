## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 6.31, < 7 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 6.41.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_cloud-nat"></a> [cloud-nat](#module\_cloud-nat) | terraform-google-modules/cloud-nat/google | 5.3.0 |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | terraform-google-modules/network/google | 11.1.1 |

## Resources

| Name | Type |
|------|------|
| [google_compute_global_address.private_ip_address](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_global_address) | resource |
| [google_service_networking_connection.private_vpc_connection](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_networking_connection) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_create_router"></a> [create\_router](#input\_create\_router) | Whether to create a router | `bool` | `true` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_log_config_enable"></a> [log\_config\_enable](#input\_log\_config\_enable) | Enable logging for the network | `bool` | `true` | no |
| <a name="input_log_config_filter"></a> [log\_config\_filter](#input\_log\_config\_filter) | Filter for logging | `string` | `"ERRORS_ONLY"` | no |
| <a name="input_mtu"></a> [mtu](#input\_mtu) | MTU for the network | `number` | `1460` | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefix to be used for resource names | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The ID of the project where resources will be created | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | The region where resources will be created | `string` | n/a | yes |
| <a name="input_router_asn"></a> [router\_asn](#input\_router\_asn) | Router ASN | `string` | `"64514"` | no |
| <a name="input_routes"></a> [routes](#input\_routes) | Additional routes for the network (beyond the default route managed internally) | `list(any)` | `[]` | no |
| <a name="input_source_subnetwork_ip_ranges_to_nat"></a> [source\_subnetwork\_ip\_ranges\_to\_nat](#input\_source\_subnetwork\_ip\_ranges\_to\_nat) | Source subnetwork IP ranges to NAT | `string` | `"ALL_SUBNETWORKS_ALL_IP_RANGES"` | no |
| <a name="input_subnets"></a> [subnets](#input\_subnets) | List of subnet configurations including primary CIDR and secondary ranges | <pre>list(object({<br/>    name           = string<br/>    cidr           = string<br/>    region         = string<br/>    private_access = optional(bool, true)<br/>    secondary_ranges = optional(list(object({<br/>      range_name    = string<br/>      ip_cidr_range = string<br/>    })), [])<br/>  }))</pre> | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_nat_name"></a> [nat\_name](#output\_nat\_name) | The name of the Cloud NAT |
| <a name="output_nat_region"></a> [nat\_region](#output\_nat\_region) | The region of the Cloud NAT |
| <a name="output_network_id"></a> [network\_id](#output\_network\_id) | The ID of the VPC network |
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | The name of the VPC network |
| <a name="output_network_self_link"></a> [network\_self\_link](#output\_network\_self\_link) | The URI of the VPC network |
| <a name="output_private_vpc_connection"></a> [private\_vpc\_connection](#output\_private\_vpc\_connection) | The private VPC connection |
| <a name="output_router_name"></a> [router\_name](#output\_router\_name) | The name of the Cloud Router |
| <a name="output_subnets"></a> [subnets](#output\_subnets) | A map of subnet outputs |
| <a name="output_subnets_ids"></a> [subnets\_ids](#output\_subnets\_ids) | The IDs of the subnets |
| <a name="output_subnets_ips"></a> [subnets\_ips](#output\_subnets\_ips) | The IPs and CIDRs of the subnets |
| <a name="output_subnets_names"></a> [subnets\_names](#output\_subnets\_names) | The names of the subnets |
| <a name="output_subnets_regions"></a> [subnets\_regions](#output\_subnets\_regions) | The regions where the subnets are created |
| <a name="output_subnets_secondary_ranges"></a> [subnets\_secondary\_ranges](#output\_subnets\_secondary\_ranges) | The secondary ranges associated with these subnets |
| <a name="output_subnets_self_links"></a> [subnets\_self\_links](#output\_subnets\_self\_links) | The self-links of the subnets |
