## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 4.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 4.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_route53_record.balancerd](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.console](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_balancerd_domain_name"></a> [balancerd\_domain\_name](#input\_balancerd\_domain\_name) | The domain name for balancerd. | `string` | n/a | yes |
| <a name="input_console_domain_name"></a> [console\_domain\_name](#input\_console\_domain\_name) | The domain name for the console. | `string` | n/a | yes |
| <a name="input_hosted_zone_id"></a> [hosted\_zone\_id](#input\_hosted\_zone\_id) | The Route53 hosted zone ID. | `string` | n/a | yes |
| <a name="input_nlb_dns_name"></a> [nlb\_dns\_name](#input\_nlb\_dns\_name) | The DNS name of the NLB. | `string` | n/a | yes |
| <a name="input_nlb_zone_id"></a> [nlb\_zone\_id](#input\_nlb\_zone\_id) | The hosted zone ID of the NLB (for ALIAS records). | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_balancerd_fqdn"></a> [balancerd\_fqdn](#output\_balancerd\_fqdn) | The FQDN of the balancerd DNS record. |
| <a name="output_console_fqdn"></a> [console\_fqdn](#output\_console\_fqdn) | The FQDN of the console DNS record. |
