## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0, < 5.101.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 2.0, < 2.18.0 |
| <a name="requirement_kubectl"></a> [kubectl](#requirement\_kubectl) | 2.4.1 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 2.0, < 2.39.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.0, < 3.10.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 5.0, < 5.101.0 |
| <a name="provider_kubectl"></a> [kubectl](#provider\_kubectl) | 2.4.1 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_lb_listener.listener](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_target_group.target_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [kubectl_manifest.target_group_binding](https://registry.terraform.io/providers/alekc/kubectl/2.4.1/docs/resources/manifest) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_health_check_path"></a> [health\_check\_path](#input\_health\_check\_path) | The URL path for target group health checks | `string` | n/a | yes |
| <a name="input_listener_port"></a> [listener\_port](#input\_listener\_port) | Port the NLB listener binds to. Defaults to var.port when null; set explicitly to expose the target on a different external port. | `number` | `null` | no |
| <a name="input_name"></a> [name](#input\_name) | Name for Target Groups and TargetGroupBindings | `string` | n/a | yes |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Kubernetes namespace in which to install TargetGroupBindings | `string` | n/a | yes |
| <a name="input_nlb_arn"></a> [nlb\_arn](#input\_nlb\_arn) | ARN of the NLB | `string` | n/a | yes |
| <a name="input_port"></a> [port](#input\_port) | Port on the target (Kubernetes service and target group). By default the NLB listener also uses this port; override listener\_port to expose a different port externally (e.g. 443 -> 8080). | `number` | n/a | yes |
| <a name="input_preserve_client_ip"></a> [preserve\_client\_ip](#input\_preserve\_client\_ip) | Whether to preserve the client IP address | `bool` | `true` | no |
| <a name="input_service_name"></a> [service\_name](#input\_service\_name) | The name of the Kubernetes service to connect to | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the VPC | `string` | n/a | yes |

## Outputs

No outputs.
