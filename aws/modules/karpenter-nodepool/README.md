## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0, < 5.101.0 |
| <a name="requirement_deepmerge"></a> [deepmerge](#requirement\_deepmerge) | ~> 1.0, < 1.4.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 2.0, < 2.18.0 |
| <a name="requirement_kubectl"></a> [kubectl](#requirement\_kubectl) | 2.4.1 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 2.0, < 2.39.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.0, < 3.10.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_kubectl"></a> [kubectl](#provider\_kubectl) | 2.4.1 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [kubectl_manifest.nodepool](https://registry.terraform.io/providers/alekc/kubectl/2.4.1/docs/resources/manifest) | resource |
| [terraform_data.destroyer](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_disruption"></a> [disruption](#input\_disruption) | Configuration for node disruption. | `any` | <pre>{<br/>  "budgets": [<br/>    {<br/>      "nodes": "10%"<br/>    }<br/>  ],<br/>  "consolidateAfter": "60s",<br/>  "consolidationPolicy": "WhenEmpty"<br/>}</pre> | no |
| <a name="input_expire_after"></a> [expire\_after](#input\_expire\_after) | Time after which the node will expire. | `string` | `"Never"` | no |
| <a name="input_instance_types"></a> [instance\_types](#input\_instance\_types) | List of instance types to support. | `list(string)` | n/a | yes |
| <a name="input_kubeconfig_data"></a> [kubeconfig\_data](#input\_kubeconfig\_data) | Contents of the kubeconfig used for cleanup of EC2 instances on destroy. | `string` | n/a | yes |
| <a name="input_limits"></a> [limits](#input\_limits) | Resource limits for the NodePool, e.g. { cpu = "1000" }. Karpenter stops<br/>provisioning new nodes from this pool once the total resources of its<br/>nodes reach these limits; existing nodes are unaffected. Setting<br/>{ cpu = "0" } prevents the pool from provisioning any new nodes, which<br/>is useful when migrating workloads to another pool. Limits are not part<br/>of the NodePool template, so changing them does not drift-replace<br/>existing nodes. | `map(string)` | `null` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the NodePool. | `string` | n/a | yes |
| <a name="input_node_labels"></a> [node\_labels](#input\_node\_labels) | Labels to apply to created Kubernetes nodes. | `map(string)` | n/a | yes |
| <a name="input_node_taints"></a> [node\_taints](#input\_node\_taints) | Taints to apply to the node. | <pre>list(object({<br/>    key    = string<br/>    value  = string<br/>    effect = string<br/>  }))</pre> | `null` | no |
| <a name="input_nodeclass_name"></a> [nodeclass\_name](#input\_nodeclass\_name) | Name of the EC2NodeClass. | `string` | n/a | yes |
| <a name="input_termination_grace_period"></a> [termination\_grace\_period](#input\_termination\_grace\_period) | Maximum time Karpenter will wait for pods to drain before forcefully<br/>terminating a node, e.g. "300s". When set, Karpenter will disrupt nodes<br/>(e.g. on drift after an instance type change) even if they run pods with<br/>the karpenter.sh/do-not-disrupt annotation or blocking PDBs; those pods<br/>are only protected until the node's termination deadline, after which<br/>they are evicted. Leave null so that do-not-disrupt pods (such as<br/>Materialize instance pods) block disruption until they are removed by a<br/>Materialize rollout. | `string` | `null` | no |

## Outputs

No outputs.
