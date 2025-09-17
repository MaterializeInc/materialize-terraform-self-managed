## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 2.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | ~> 2.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [kubernetes_service.balancerd_load_balancer](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service) | resource |
| [kubernetes_service.console_load_balancer](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_instance_name"></a> [instance\_name](#input\_instance\_name) | The name of the Materialize instance. | `string` | n/a | yes |
| <a name="input_internal"></a> [internal](#input\_internal) | Whether the load balancer is internal to the VPC. | `bool` | `true` | no |
| <a name="input_materialize_balancerd_https_port"></a> [materialize\_balancerd\_https\_port](#input\_materialize\_balancerd\_https\_port) | HTTPS port configuration for Materialize balancerd service | `number` | `6876` | no |
| <a name="input_materialize_balancerd_sql_port"></a> [materialize\_balancerd\_sql\_port](#input\_materialize\_balancerd\_sql\_port) | SQL port configuration for Materialize balancerd service | `number` | `6875` | no |
| <a name="input_materialize_console_port"></a> [materialize\_console\_port](#input\_materialize\_console\_port) | Port configuration for Materialize console service | `number` | `8080` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | The kubernetes namespace to create the LoadBalancer Service in. | `string` | n/a | yes |
| <a name="input_resource_id"></a> [resource\_id](#input\_resource\_id) | The resource\_id in the Materialize status. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_balancerd_load_balancer_ip"></a> [balancerd\_load\_balancer\_ip](#output\_balancerd\_load\_balancer\_ip) | IP address of load balancer pointing at balancerd. |
| <a name="output_console_load_balancer_ip"></a> [console\_load\_balancer\_ip](#output\_console\_load\_balancer\_ip) | IP address of load balancer pointing at the web console. |
| <a name="output_instance_name"></a> [instance\_name](#output\_instance\_name) | The name of the Materialize instance. |
