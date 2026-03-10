## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 4.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | >= 4.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [google_dns_record_set.balancerd](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/dns_record_set) | resource |
| [google_dns_record_set.console](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/dns_record_set) | resource |
| [google_dns_managed_zone.zone](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/dns_managed_zone) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_balancerd_hostname"></a> [balancerd\_hostname](#input\_balancerd\_hostname) | The hostname for balancerd (without trailing dot). | `string` | n/a | yes |
| <a name="input_balancerd_ip"></a> [balancerd\_ip](#input\_balancerd\_ip) | The IP address for the balancerd A record. | `string` | n/a | yes |
| <a name="input_console_hostname"></a> [console\_hostname](#input\_console\_hostname) | The hostname for the console (without trailing dot). | `string` | n/a | yes |
| <a name="input_console_ip"></a> [console\_ip](#input\_console\_ip) | The IP address for the console A record. | `string` | n/a | yes |
| <a name="input_dns_ttl"></a> [dns\_ttl](#input\_dns\_ttl) | TTL for DNS records in seconds. | `number` | `300` | no |
| <a name="input_dns_zone_name"></a> [dns\_zone\_name](#input\_dns\_zone\_name) | The name of the Cloud DNS managed zone. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The GCP project ID. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_balancerd_fqdn"></a> [balancerd\_fqdn](#output\_balancerd\_fqdn) | The FQDN of the balancerd DNS record. |
| <a name="output_console_fqdn"></a> [console\_fqdn](#output\_console\_fqdn) | The FQDN of the console DNS record. |
