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
| <a name="module_rustfs"></a> [rustfs](#module\_rustfs) | ../../../kubernetes/modules/object-store-rustfs | n/a |
| <a name="module_storage_pool"></a> [storage\_pool](#module\_storage\_pool) | ../storage-node-pool | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_ami_selector_terms"></a> [ami\_selector\_terms](#input\_ami\_selector\_terms) | AMI selector terms for the storage node class. | `any` | <pre>[<br/>  {<br/>    "alias": "bottlerocket@latest"<br/>  }<br/>]</pre> | no |
| <a name="input_bucket"></a> [bucket](#input\_bucket) | Bucket created for Materialize's persist data. | `string` | `"materialize"` | no |
| <a name="input_drive_size"></a> [drive\_size](#input\_drive\_size) | Size of each volume. | `string` | `"500Gi"` | no |
| <a name="input_drives_per_replica"></a> [drives\_per\_replica](#input\_drives\_per\_replica) | Volumes per pod. One suits the single-NVMe instance families; raise it only on a family with several devices per node. | `number` | `1` | no |
| <a name="input_image"></a> [image](#input\_image) | RustFS server image. | `string` | `"rustfs/rustfs:1.0.0-rc.5"` | no |
| <a name="input_install_csi_driver"></a> [install\_csi\_driver](#input\_install\_csi\_driver) | Whether this store's node pool installs the LVM CSI driver. Set false for a second store sharing a cluster with one that already did. | `bool` | `true` | no |
| <a name="input_instance_profile"></a> [instance\_profile](#input\_instance\_profile) | Instance profile for storage nodes, from the karpenter module. | `string` | n/a | yes |
| <a name="input_instance_types"></a> [instance\_types](#input\_instance\_types) | Instance types for the storage node pool. Needs a family with local NVMe and bandwidth the store will not outrun; see the node pool module for why the burstable sizes mislead a benchmark. | `list(string)` | <pre>[<br/>  "i8g.8xlarge"<br/>]</pre> | no |
| <a name="input_kubeconfig_data"></a> [kubeconfig\_data](#input\_kubeconfig\_data) | Contents of the kubeconfig, used by the node pool module to clean up EC2 instances on destroy. | `string` | n/a | yes |
| <a name="input_lvm_chart_version"></a> [lvm\_chart\_version](#input\_lvm\_chart\_version) | Version of the openebs lvm-localpv Helm chart. | `string` | `"1.6.2"` | no |
| <a name="input_name"></a> [name](#input\_name) | Name prefix for the store, its node pool and their labels. | `string` | `"rustfs"` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace to deploy RustFS into. | `string` | `"object-store"` | no |
| <a name="input_node_limits"></a> [node\_limits](#input\_node\_limits) | Resource ceiling for the storage node pool. | `map(string)` | <pre>{<br/>  "cpu": "256"<br/>}</pre> | no |
| <a name="input_region"></a> [region](#input\_region) | Region reported to S3 clients. RustFS ignores it, but the AWS SDKs require one to sign requests. | `string` | `"us-east-1"` | no |
| <a name="input_replicas"></a> [replicas](#input\_replicas) | RustFS server pods.<br/><br/>Each claims a volume from the instance store of the node it lands on, so<br/>this should not exceed the number of nodes the pool will run. More than one<br/>replica erasure-codes across pods, which needs `replicas *<br/>drives_per_replica` to be at least 4. | `number` | `4` | no |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | Security groups for storage nodes, normally the EKS node security group. | `list(string)` | n/a | yes |
| <a name="input_storage_class_name"></a> [storage\_class\_name](#input\_storage\_class\_name) | Name of the StorageClass provisioned from the volume group. | `string` | `"instance-store"` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnets storage nodes may launch into. Private subnets across AZs. | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the node class. | `map(string)` | `{}` | no |
| <a name="input_volume_group"></a> [volume\_group](#input\_volume\_group) | Name of the LVM volume group built from the instance store. | `string` | `"instance-store-vg"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bucket"></a> [bucket](#output\_bucket) | Bucket created for persist data. |
| <a name="output_endpoint"></a> [endpoint](#output\_endpoint) | In-cluster S3 endpoint for the store. |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace the store runs in. |
| <a name="output_node_selector"></a> [node\_selector](#output\_node\_selector) | Label selecting the storage nodes, for pinning a benchmark client alongside the store. |
| <a name="output_persist_backend_url"></a> [persist\_backend\_url](#output\_persist\_backend\_url) | S3 connection URL for the store, in the form `materialize-instance` expects for `persist_backend_url`. |
| <a name="output_storage_class_name"></a> [storage\_class\_name](#output\_storage\_class\_name) | StorageClass backing the store, provisioned from the nodes' instance store. |
| <a name="output_tolerations"></a> [tolerations](#output\_tolerations) | Tolerations needed to schedule onto the storage nodes. |
