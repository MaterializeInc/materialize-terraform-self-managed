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
| <a name="module_ceph"></a> [ceph](#module\_ceph) | ../../../kubernetes/modules/object-store-rook-ceph | n/a |
| <a name="module_storage_pool"></a> [storage\_pool](#module\_storage\_pool) | ../storage-node-pool | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_ami_selector_terms"></a> [ami\_selector\_terms](#input\_ami\_selector\_terms) | AMI selector terms for the storage node class. | `any` | <pre>[<br/>  {<br/>    "alias": "bottlerocket@latest"<br/>  }<br/>]</pre> | no |
| <a name="input_bucket"></a> [bucket](#input\_bucket) | Bucket created for Materialize's persist data. | `string` | `"materialize"` | no |
| <a name="input_data_dir_host_path"></a> [data\_dir\_host\_path](#input\_data\_dir\_host\_path) | Host path where Rook keeps daemon state. Must be empty of any previous cluster's state. | `string` | `"/var/lib/rook"` | no |
| <a name="input_gateway_instances"></a> [gateway\_instances](#input\_gateway\_instances) | Number of RGW gateway pods serving S3. This is the request path, so it is the first thing to scale for throughput. | `number` | `2` | no |
| <a name="input_install_csi_driver"></a> [install\_csi\_driver](#input\_install\_csi\_driver) | Whether this store's node pool installs the LVM CSI driver. Set false for a second store sharing a cluster with one that already did. | `bool` | `true` | no |
| <a name="input_instance_profile"></a> [instance\_profile](#input\_instance\_profile) | Instance profile for storage nodes, from the karpenter module. | `string` | n/a | yes |
| <a name="input_instance_types"></a> [instance\_types](#input\_instance\_types) | Instance types for the storage node pool. Needs a family with local NVMe and bandwidth the store will not outrun; see the node pool module for why the burstable sizes mislead a benchmark. | `list(string)` | <pre>[<br/>  "i8g.8xlarge"<br/>]</pre> | no |
| <a name="input_kubeconfig_data"></a> [kubeconfig\_data](#input\_kubeconfig\_data) | Contents of the kubeconfig, used by the node pool module to clean up EC2 instances on destroy. | `string` | n/a | yes |
| <a name="input_lvm_chart_version"></a> [lvm\_chart\_version](#input\_lvm\_chart\_version) | Version of the openebs lvm-localpv Helm chart. | `string` | `"1.6.2"` | no |
| <a name="input_mon_count"></a> [mon\_count](#input\_mon\_count) | Number of Ceph monitors. Three is the smallest count that tolerates losing one. | `number` | `3` | no |
| <a name="input_name"></a> [name](#input\_name) | Name prefix for the Ceph cluster, object store, node pool and their labels. | `string` | `"ceph"` | no |
| <a name="input_node_limits"></a> [node\_limits](#input\_node\_limits) | Resource ceiling for the storage node pool. | `map(string)` | <pre>{<br/>  "cpu": "256"<br/>}</pre> | no |
| <a name="input_osd_count"></a> [osd\_count](#input\_osd\_count) | Number of OSDs, one per volume from the storage class.<br/><br/>Each needs a node with room in its volume group, so this should not exceed<br/>the number of nodes the pool will run. | `number` | `4` | no |
| <a name="input_osd_size"></a> [osd\_size](#input\_osd\_size) | Size of each OSD volume. | `string` | `"500Gi"` | no |
| <a name="input_region"></a> [region](#input\_region) | Region reported to S3 clients. RGW ignores it, but the AWS SDKs require one to sign requests. | `string` | `"us-east-1"` | no |
| <a name="input_replica_size"></a> [replica\_size](#input\_replica\_size) | Replica count for the object store's metadata and data pools. | `number` | `3` | no |
| <a name="input_rgw_chunk_size_bytes"></a> [rgw\_chunk\_size\_bytes](#input\_rgw\_chunk\_size\_bytes) | Value for `rgw_max_chunk_size` and `rgw_obj_stripe_size`.<br/><br/>Both default to 4 MiB in Ceph, which splits every persist blob above that<br/>into several RADOS objects. persist uploads 8 MiB multipart parts and writes<br/>blobs up to a 128 MiB target, so the stock value turns one blob write into a<br/>dozen or more internal round trips. | `number` | `16777216` | no |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | Security groups for storage nodes, normally the EKS node security group. | `list(string)` | n/a | yes |
| <a name="input_storage_class_name"></a> [storage\_class\_name](#input\_storage\_class\_name) | Name of the StorageClass provisioned from the volume group. | `string` | `"instance-store"` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnets storage nodes may launch into. Private subnets across AZs. | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the node class. | `map(string)` | `{}` | no |
| <a name="input_volume_group"></a> [volume\_group](#input\_volume\_group) | Name of the LVM volume group built from the instance store. | `string` | `"instance-store-vg"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bucket"></a> [bucket](#output\_bucket) | Bucket created for persist data. |
| <a name="output_endpoint"></a> [endpoint](#output\_endpoint) | In-cluster S3 endpoint for the RGW gateway. |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace Rook and Ceph run in. |
| <a name="output_node_selector"></a> [node\_selector](#output\_node\_selector) | Label selecting the storage nodes, for pinning a benchmark client alongside the store. |
| <a name="output_persist_backend_url"></a> [persist\_backend\_url](#output\_persist\_backend\_url) | S3 connection URL for the store, in the form `materialize-instance` expects for `persist_backend_url`. |
| <a name="output_storage_class_name"></a> [storage\_class\_name](#output\_storage\_class\_name) | StorageClass backing the OSDs, provisioned from the nodes' instance store. |
| <a name="output_tolerations"></a> [tolerations](#output\_tolerations) | Tolerations needed to schedule onto the storage nodes. |
