## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 2.5.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.10.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 5.0 |
| <a name="provider_helm"></a> [helm](#provider\_helm) | >= 2.5.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | >= 2.10.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_iam_role.vpc_cni](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.vpc_cni](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [helm_release.vpc_cni](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_annotations.vpc_cni_service_account](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/annotations) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_chart_version"></a> [chart\_version](#input\_chart\_version) | Version of the AWS VPC CNI Helm chart | `string` | `"1.19.0"` | no |
| <a name="input_enable_network_policy"></a> [enable\_network\_policy](#input\_enable\_network\_policy) | Enable Kubernetes NetworkPolicy support. Requires VPC CNI v1.14+ and Kubernetes 1.25+. | `bool` | `true` | no |
| <a name="input_enable_policy_event_logs"></a> [enable\_policy\_event\_logs](#input\_enable\_policy\_event\_logs) | Enable logging of network policy events to node/pod logs | `bool` | `true` | no |
| <a name="input_enable_prefix_delegation"></a> [enable\_prefix\_delegation](#input\_enable\_prefix\_delegation) | Enable prefix delegation for higher pod density per node | `bool` | `false` | no |
| <a name="input_minimum_ip_target"></a> [minimum\_ip\_target](#input\_minimum\_ip\_target) | Minimum number of IP addresses to keep available per node | `number` | `null` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix for all resource names | `string` | n/a | yes |
| <a name="input_oidc_issuer_url"></a> [oidc\_issuer\_url](#input\_oidc\_issuer\_url) | URL of the OIDC issuer for the EKS cluster | `string` | n/a | yes |
| <a name="input_oidc_provider_arn"></a> [oidc\_provider\_arn](#input\_oidc\_provider\_arn) | ARN of the OIDC provider for the EKS cluster | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_warm_ip_target"></a> [warm\_ip\_target](#input\_warm\_ip\_target) | Number of free IP addresses to maintain per node | `number` | `null` | no |
| <a name="input_warm_prefix_target"></a> [warm\_prefix\_target](#input\_warm\_prefix\_target) | Number of free prefixes to maintain per node when prefix delegation is enabled | `number` | `1` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_helm_release_name"></a> [helm\_release\_name](#output\_helm\_release\_name) | Name of the Helm release |
| <a name="output_helm_release_version"></a> [helm\_release\_version](#output\_helm\_release\_version) | Version of the Helm chart installed |
| <a name="output_iam_role_arn"></a> [iam\_role\_arn](#output\_iam\_role\_arn) | ARN of the IAM role used by the VPC CNI |
| <a name="output_iam_role_name"></a> [iam\_role\_name](#output\_iam\_role\_name) | Name of the IAM role used by the VPC CNI |
| <a name="output_network_policy_enabled"></a> [network\_policy\_enabled](#output\_network\_policy\_enabled) | Whether network policy support is enabled |
