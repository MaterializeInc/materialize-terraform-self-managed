## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 2.5.0, < 2.18.0 |
| <a name="requirement_kubectl"></a> [kubectl](#requirement\_kubectl) | 2.4.1 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.10.0, < 2.39.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.1, < 3.10.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_node_class"></a> [node\_class](#module\_node\_class) | ../karpenter-ec2nodeclass | n/a |
| <a name="module_node_pool"></a> [node\_pool](#module\_node\_pool) | ../karpenter-nodepool | n/a |
| <a name="module_storage_class"></a> [storage\_class](#module\_storage\_class) | ../../../kubernetes/modules/lvm-local-storage | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_ami_selector_terms"></a> [ami\_selector\_terms](#input\_ami\_selector\_terms) | AMI selector terms for the node class. | `any` | <pre>[<br/>  {<br/>    "alias": "bottlerocket@latest"<br/>  }<br/>]</pre> | no |
| <a name="input_instance_profile"></a> [instance\_profile](#input\_instance\_profile) | Instance profile for the nodes, from the karpenter module. | `string` | n/a | yes |
| <a name="input_instance_types"></a> [instance\_types](#input\_instance\_types) | Instance types for the pool.<br/><br/>Needs a family with local NVMe, since the point of this module is to keep a<br/>workload off EBS: the `i` families qualify, `m`/`c`/`r` generally do not.<br/>Every type listed must appear in the node class module's<br/>`instance-descriptions.json`, which is what sizes the kubelet reservations. | `list(string)` | <pre>[<br/>  "i8g.2xlarge"<br/>]</pre> | no |
| <a name="input_kubeconfig_data"></a> [kubeconfig\_data](#input\_kubeconfig\_data) | Contents of the kubeconfig, used by the node pool module to clean up EC2 instances on destroy. | `string` | n/a | yes |
| <a name="input_limits"></a> [limits](#input\_limits) | Resource ceiling for the pool. Karpenter stops adding nodes once the pool reaches it. | `map(string)` | <pre>{<br/>  "cpu": "64"<br/>}</pre> | no |
| <a name="input_lvm_chart_version"></a> [lvm\_chart\_version](#input\_lvm\_chart\_version) | Version of the openebs lvm-localpv Helm chart. | `string` | `"1.6.2"` | no |
| <a name="input_name"></a> [name](#input\_name) | Name for the node class, node pool and the label that selects its nodes. | `string` | `"storage"` | no |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | Security groups for the nodes, normally the EKS node security group. | `list(string)` | n/a | yes |
| <a name="input_storage_class_name"></a> [storage\_class\_name](#input\_storage\_class\_name) | Name of the StorageClass provisioned from the volume group. | `string` | `"instance-store"` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnets the nodes may launch into. Private subnets across AZs. | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the node class. | `map(string)` | `{}` | no |
| <a name="input_volume_group"></a> [volume\_group](#input\_volume\_group) | Name of the LVM volume group built from the instance store. | `string` | `"instance-store-vg"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_name"></a> [name](#output\_name) | Name of the node class and node pool. |
| <a name="output_node_selector"></a> [node\_selector](#output\_node\_selector) | Label selecting this pool's nodes. |
| <a name="output_storage_class_name"></a> [storage\_class\_name](#output\_storage\_class\_name) | StorageClass provisioned from the nodes' instance store. A workload must use this class to land on local NVMe. |
| <a name="output_tolerations"></a> [tolerations](#output\_tolerations) | Tolerations required to schedule onto this pool, which is tainted so nothing else lands there. |
| <a name="output_volume_group"></a> [volume\_group](#output\_volume\_group) | LVM volume group built from the instance store. |
