## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_kubectl"></a> [kubectl](#requirement\_kubectl) | 2.4.1 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.10.0, < 2.39.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_kubectl"></a> [kubectl](#provider\_kubectl) | 2.4.1 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | >= 2.10.0, < 2.39.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [kubectl_manifest.nodeclass](https://registry.terraform.io/providers/alekc/kubectl/2.4.1/docs/resources/manifest) | resource |
| [kubectl_manifest.nodepool](https://registry.terraform.io/providers/alekc/kubectl/2.4.1/docs/resources/manifest) | resource |
| [kubernetes_cluster_role.disk_setup](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/cluster_role) | resource |
| [kubernetes_cluster_role_binding.disk_setup](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/cluster_role_binding) | resource |
| [kubernetes_daemonset.disk_setup](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/daemonset) | resource |
| [kubernetes_namespace.disk_setup](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace) | resource |
| [kubernetes_service_account.disk_setup](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service_account) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_disk_setup_container_resource_config"></a> [disk\_setup\_container\_resource\_config](#input\_disk\_setup\_container\_resource\_config) | Resource configuration for disk setup init container | <pre>object({<br/>    memory_limit   = string<br/>    memory_request = string<br/>    cpu_request    = string<br/>  })</pre> | <pre>{<br/>  "cpu_request": "50m",<br/>  "memory_limit": "128Mi",<br/>  "memory_request": "128Mi"<br/>}</pre> | no |
| <a name="input_disk_setup_image"></a> [disk\_setup\_image](#input\_disk\_setup\_image) | Docker image for the disk setup script | `string` | `"materialize/ephemeral-storage-setup-image:v0.4.1"` | no |
| <a name="input_disk_setup_name"></a> [disk\_setup\_name](#input\_disk\_setup\_name) | Name used for disk setup Kubernetes resources (namespace, daemonset, service account, cluster role, cluster role binding). Defaults to "<name>-disk-setup". | `string` | `null` | no |
| <a name="input_disruption"></a> [disruption](#input\_disruption) | Configuration for node disruption. | `any` | <pre>{<br/>  "budgets": [<br/>    {<br/>      "nodes": "10%"<br/>    }<br/>  ],<br/>  "consolidateAfter": "60s",<br/>  "consolidationPolicy": "WhenEmpty"<br/>}</pre> | no |
| <a name="input_expire_after"></a> [expire\_after](#input\_expire\_after) | Time after which the node will expire. | `string` | `"Never"` | no |
| <a name="input_limits"></a> [limits](#input\_limits) | Resource limits for the NodePool, e.g. { cpu = "1000" }. Karpenter stops<br/>provisioning new nodes from this pool once the total resources of its<br/>nodes reach these limits; existing nodes are unaffected. Setting<br/>{ cpu = "0" } prevents the pool from provisioning any new nodes. | `map(string)` | `null` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region of the AKS cluster. Used to build zone labels from `zones`. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name of the Karpenter NodePool and AKSNodeClass. | `string` | n/a | yes |
| <a name="input_node_labels"></a> [node\_labels](#input\_node\_labels) | Labels to apply to created Kubernetes nodes. | `map(string)` | `{}` | no |
| <a name="input_node_taints"></a> [node\_taints](#input\_node\_taints) | Taints to apply to created Kubernetes nodes. | <pre>list(object({<br/>    key    = string<br/>    value  = string<br/>    effect = string<br/>  }))</pre> | `[]` | no |
| <a name="input_os_disk_size_gb"></a> [os\_disk\_size\_gb](#input\_os\_disk\_size\_gb) | Size of each node's managed OS disk in GB. | `number` | `100` | no |
| <a name="input_pause_container_resource_config"></a> [pause\_container\_resource\_config](#input\_pause\_container\_resource\_config) | Resource configuration for pause container | <pre>object({<br/>    memory_limit   = string<br/>    memory_request = string<br/>    cpu_request    = string<br/>  })</pre> | <pre>{<br/>  "cpu_request": "1m",<br/>  "memory_limit": "8Mi",<br/>  "memory_request": "8Mi"<br/>}</pre> | no |
| <a name="input_swap_enabled"></a> [swap\_enabled](#input\_swap\_enabled) | Whether to enable swap on the local NVMe disks. | `bool` | `false` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Azure tags to apply to the VMs. | `map(string)` | `{}` | no |
| <a name="input_termination_grace_period"></a> [termination\_grace\_period](#input\_termination\_grace\_period) | Maximum time Karpenter will wait for pods to drain before forcefully<br/>terminating a node, e.g. "300s". When set, Karpenter will disrupt nodes<br/>(e.g. on drift after a VM size change) even if they run pods with<br/>the karpenter.sh/do-not-disrupt annotation or blocking PDBs. Leave null<br/>so that do-not-disrupt pods (such as Materialize instance pods) block<br/>disruption until they are removed by a Materialize rollout. | `string` | `null` | no |
| <a name="input_vm_sizes"></a> [vm\_sizes](#input\_vm\_sizes) | VM sizes Node Auto Provisioning may create, e.g. ["Standard\_E4pds\_v6"]. For swap, use sizes with local NVMe disks. | `list(string)` | n/a | yes |
| <a name="input_zones"></a> [zones](#input\_zones) | Availability zones ("1", "2", "3") to provision nodes in. When null, Node Auto Provisioning chooses. | `list(string)` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_nodeclass_name"></a> [nodeclass\_name](#output\_nodeclass\_name) | The name of the AKSNodeClass |
| <a name="output_nodepool_name"></a> [nodepool\_name](#output\_nodepool\_name) | The name of the Karpenter NodePool |
