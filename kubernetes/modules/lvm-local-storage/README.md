## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 2.5.0, < 2.18.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.10.0, < 2.39.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_helm"></a> [helm](#provider\_helm) | >= 2.5.0, < 2.18.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | >= 2.10.0, < 2.39.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [helm_release.lvm_localpv](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_namespace.this](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace) | resource |
| [kubernetes_storage_class.instance_store](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/storage_class) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_chart_version"></a> [chart\_version](#input\_chart\_version) | Version of the openebs lvm-localpv Helm chart. | `string` | `"1.6.2"` | no |
| <a name="input_create_namespace"></a> [create\_namespace](#input\_create\_namespace) | Whether to create the namespace. Set false when another module already owns it. | `bool` | `true` | no |
| <a name="input_fs_type"></a> [fs\_type](#input\_fs\_type) | Filesystem written onto provisioned logical volumes. | `string` | `"ext4"` | no |
| <a name="input_install_timeout"></a> [install\_timeout](#input\_install\_timeout) | Seconds to wait for the chart to install. | `number` | `600` | no |
| <a name="input_is_default_class"></a> [is\_default\_class](#input\_is\_default\_class) | Whether to mark this StorageClass default.<br/><br/>Leave false on AWS, where the EBS CSI driver's `gp3` class is already the<br/>default. A local volume pins its pod to one node for the pod's lifetime,<br/>which is right for an object store and wrong for most other workloads. | `bool` | `false` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace to deploy the LVM CSI driver into. | `string` | `"openebs"` | no |
| <a name="input_node_selector"></a> [node\_selector](#input\_node\_selector) | Node selector for the CSI node plugin. Restrict this to the pool whose nodes actually have a volume group. | `map(string)` | `{}` | no |
| <a name="input_storage_class_name"></a> [storage\_class\_name](#input\_storage\_class\_name) | Name of the StorageClass created for LVM-backed volumes. | `string` | `"instance-store"` | no |
| <a name="input_tolerations"></a> [tolerations](#input\_tolerations) | Tolerations for the CSI node plugin, so it can run on a tainted storage node pool. | <pre>list(object({<br/>    key      = string<br/>    operator = string<br/>    value    = optional(string)<br/>    effect   = string<br/>  }))</pre> | `[]` | no |
| <a name="input_volume_group"></a> [volume\_group](#input\_volume\_group) | LVM volume group the driver carves volumes out of.<br/><br/>Must match `ephemeral_storage_vg_name` on the node class that ran<br/>`ephemeral-storage-setup lvm`, or the driver will find no group to<br/>provision from and PVCs will stay Pending. | `string` | `"instance-store-vg"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace the CSI driver runs in. |
| <a name="output_storage_class_name"></a> [storage\_class\_name](#output\_storage\_class\_name) | Name of the StorageClass backed by the instance store volume group. |
| <a name="output_volume_group"></a> [volume\_group](#output\_volume\_group) | LVM volume group the StorageClass provisions from. |
