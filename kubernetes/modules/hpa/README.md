## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.8 |
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
| [kubernetes_horizontal_pod_autoscaler_v2.this](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/horizontal_pod_autoscaler_v2) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cpu_target_utilization"></a> [cpu\_target\_utilization](#input\_cpu\_target\_utilization) | Target CPU utilization percentage | `number` | `60` | no |
| <a name="input_max_replicas"></a> [max\_replicas](#input\_max\_replicas) | Maximum number of replicas | `number` | `100` | no |
| <a name="input_memory_target_utilization"></a> [memory\_target\_utilization](#input\_memory\_target\_utilization) | Target memory utilization percentage | `number` | `50` | no |
| <a name="input_min_replicas"></a> [min\_replicas](#input\_min\_replicas) | Minimum number of replicas | `number` | `2` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the HPA resource | `string` | n/a | yes |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace for the HPA | `string` | n/a | yes |
| <a name="input_policy_period_seconds"></a> [policy\_period\_seconds](#input\_policy\_period\_seconds) | Period in seconds for scaling policies | `number` | `15` | no |
| <a name="input_scale_down_percent_per_period"></a> [scale\_down\_percent\_per\_period](#input\_scale\_down\_percent\_per\_period) | Maximum percent to scale down per period | `number` | `100` | no |
| <a name="input_scale_down_stabilization_window"></a> [scale\_down\_stabilization\_window](#input\_scale\_down\_stabilization\_window) | Stabilization window for scale down in seconds | `number` | `600` | no |
| <a name="input_scale_up_percent_per_period"></a> [scale\_up\_percent\_per\_period](#input\_scale\_up\_percent\_per\_period) | Maximum percent to scale up per period | `number` | `100` | no |
| <a name="input_scale_up_pods_per_period"></a> [scale\_up\_pods\_per\_period](#input\_scale\_up\_pods\_per\_period) | Maximum pods to add per period during scale up | `number` | `4` | no |
| <a name="input_scale_up_stabilization_window"></a> [scale\_up\_stabilization\_window](#input\_scale\_up\_stabilization\_window) | Stabilization window for scale up in seconds | `number` | `180` | no |
| <a name="input_target_kind"></a> [target\_kind](#input\_target\_kind) | Kind of the resource to scale (Deployment, StatefulSet, ReplicaSet) | `string` | n/a | yes |
| <a name="input_target_name"></a> [target\_name](#input\_target\_name) | Name of the resource to scale | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_hpa_name"></a> [hpa\_name](#output\_hpa\_name) | Name of the HPA resource |
| <a name="output_hpa_namespace"></a> [hpa\_namespace](#output\_hpa\_namespace) | Namespace of the HPA resource |
