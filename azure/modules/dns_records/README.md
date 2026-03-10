## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 3.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_dns_a_record.balancerd](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/dns_a_record) | resource |
| [azurerm_dns_a_record.console](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/dns_a_record) | resource |
| [azurerm_dns_zone.zone](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/dns_zone) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_balancerd_domain_name"></a> [balancerd\_domain\_name](#input\_balancerd\_domain\_name) | The record name for balancerd (relative to the zone). | `string` | n/a | yes |
| <a name="input_balancerd_ip"></a> [balancerd\_ip](#input\_balancerd\_ip) | The IP address for the balancerd A record. | `string` | n/a | yes |
| <a name="input_console_domain_name"></a> [console\_domain\_name](#input\_console\_domain\_name) | The record name for the console (relative to the zone). | `string` | n/a | yes |
| <a name="input_console_ip"></a> [console\_ip](#input\_console\_ip) | The IP address for the console A record. | `string` | n/a | yes |
| <a name="input_dns_zone_name"></a> [dns\_zone\_name](#input\_dns\_zone\_name) | The name of the Azure DNS zone. | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | The resource group containing the DNS zone. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to resources. | `map(string)` | `{}` | no |
| <a name="input_ttl"></a> [ttl](#input\_ttl) | TTL for DNS records in seconds. | `number` | `300` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_balancerd_fqdn"></a> [balancerd\_fqdn](#output\_balancerd\_fqdn) | The FQDN of the balancerd DNS record. |
| <a name="output_console_fqdn"></a> [console\_fqdn](#output\_console\_fqdn) | The FQDN of the console DNS record. |
