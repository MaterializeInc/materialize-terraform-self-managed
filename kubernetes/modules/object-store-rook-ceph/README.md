## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 2.5.0, < 2.18.0 |
| <a name="requirement_kubectl"></a> [kubectl](#requirement\_kubectl) | 2.4.1 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.10.0, < 2.39.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_helm"></a> [helm](#provider\_helm) | >= 2.5.0, < 2.18.0 |
| <a name="provider_kubectl"></a> [kubectl](#provider\_kubectl) | 2.4.1 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | >= 2.10.0, < 2.39.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [helm_release.rook_operator](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubectl_manifest.ceph_cluster](https://registry.terraform.io/providers/alekc/kubectl/2.4.1/docs/resources/manifest) | resource |
| [kubectl_manifest.object_store](https://registry.terraform.io/providers/alekc/kubectl/2.4.1/docs/resources/manifest) | resource |
| [kubectl_manifest.object_store_user](https://registry.terraform.io/providers/alekc/kubectl/2.4.1/docs/resources/manifest) | resource |
| [kubernetes_config_map.ceph_config_override](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/config_map) | resource |
| [kubernetes_job.create_bucket](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/job) | resource |
| [kubernetes_namespace.this](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace) | resource |
| [kubernetes_secret.object_store_user](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/data-sources/secret) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_bucket"></a> [bucket](#input\_bucket) | Bucket created for Materialize's persist data. | `string` | `"materialize"` | no |
| <a name="input_ceph_image"></a> [ceph\_image](#input\_ceph\_image) | Ceph container image run by the daemons. | `string` | `"quay.io/ceph/ceph:v19.2.6"` | no |
| <a name="input_create_namespace"></a> [create\_namespace](#input\_create\_namespace) | Whether to create the namespace. Set false when another module already owns it. | `bool` | `true` | no |
| <a name="input_data_dir_host_path"></a> [data\_dir\_host\_path](#input\_data\_dir\_host\_path) | Host path where Rook keeps daemon state. Must be writable on every node running a Ceph daemon. | `string` | `"/var/lib/rook"` | no |
| <a name="input_device_filter"></a> [device\_filter](#input\_device\_filter) | Regex selecting which devices Rook turns into OSDs, for example `^nvme[1-9]n1$`.<br/><br/>Storage-optimized instances expose their local NVMe separately from the<br/>root volume, and this is what keeps Rook off the root volume. Ignored when<br/>`use_all_devices` is true. | `string` | `null` | no |
| <a name="input_extra_ceph_config"></a> [extra\_ceph\_config](#input\_extra\_ceph\_config) | Additional lines appended to the `[global]` section of `rook-config-override`.<br/><br/>Daemons read this ConfigMap at start-up, so the module creates it before<br/>the cluster. Changing it afterwards needs a daemon restart to take effect. | `string` | `""` | no |
| <a name="input_failure_domain"></a> [failure\_domain](#input\_failure\_domain) | CRUSH failure domain for the object store's pools. Use `osd` only when every OSD shares a node. | `string` | `"host"` | no |
| <a name="input_gateway_instances"></a> [gateway\_instances](#input\_gateway\_instances) | Number of RGW gateway pods serving S3. This is the request path, so it is the first thing to scale for throughput. | `number` | `2` | no |
| <a name="input_install_timeout"></a> [install\_timeout](#input\_install\_timeout) | Seconds to wait for the operator chart to install. | `number` | `600` | no |
| <a name="input_mon_count"></a> [mon\_count](#input\_mon\_count) | Number of Ceph monitors. Three is the smallest count that tolerates losing one; use one only for a single-node test cluster. | `number` | `3` | no |
| <a name="input_name"></a> [name](#input\_name) | Name for the Ceph cluster and object store, used for resource names and labels. | `string` | `"ceph"` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace to deploy Rook and Ceph into. Rook expects the operator and cluster to share one. | `string` | `"rook-ceph"` | no |
| <a name="input_node_selector"></a> [node\_selector](#input\_node\_selector) | Node selector for Ceph daemons. Use this to pin the store to a storage-optimized node pool. | `map(string)` | `{}` | no |
| <a name="input_object_store_user"></a> [object\_store\_user](#input\_object\_store\_user) | Name of the CephObjectStoreUser whose credentials Materialize uses. | `string` | `"persist"` | no |
| <a name="input_operator_chart_version"></a> [operator\_chart\_version](#input\_operator\_chart\_version) | Version of the rook-ceph operator Helm chart. | `string` | `"v1.16.7"` | no |
| <a name="input_osd_count"></a> [osd\_count](#input\_osd\_count) | Number of OSDs to create from `osd_storage_class`.<br/><br/>Each needs a node with room in its volume group, so this should not exceed<br/>the size of the storage node pool when the class is node-local. Ignored<br/>when `osd_storage_class` is null. | `number` | `3` | no |
| <a name="input_osd_memory_target_bytes"></a> [osd\_memory\_target\_bytes](#input\_osd\_memory\_target\_bytes) | Value for `osd_memory_target`. Null leaves Ceph's default of 4 GiB, which is appropriate when OSDs have a node to themselves. | `number` | `null` | no |
| <a name="input_osd_size"></a> [osd\_size](#input\_osd\_size) | Size of each OSD volume. Ignored when `osd_storage_class` is null. | `string` | `"500Gi"` | no |
| <a name="input_osd_storage_class"></a> [osd\_storage\_class](#input\_osd\_storage\_class) | StorageClass OSDs are provisioned from, one OSD per volume.<br/><br/>This is the path to use in a cloud, and the only one available once the<br/>node's instance store has been claimed into an LVM volume group, since Rook<br/>can no longer see raw devices. Point it at the class from<br/>`lvm-local-storage` to put OSDs on local NVMe.<br/><br/>Null instead hands Rook whole devices, using `use_all_devices` and<br/>`device_filter`, which suits bare metal. | `string` | `null` | no |
| <a name="input_region"></a> [region](#input\_region) | Region reported to S3 clients. RGW ignores it, but the AWS SDKs require one to sign requests. | `string` | `"us-east-1"` | no |
| <a name="input_replica_size"></a> [replica\_size](#input\_replica\_size) | Replica count for the object store's metadata and data pools. | `number` | `3` | no |
| <a name="input_rgw_chunk_size_bytes"></a> [rgw\_chunk\_size\_bytes](#input\_rgw\_chunk\_size\_bytes) | Value for `rgw_max_chunk_size` and `rgw_obj_stripe_size`.<br/><br/>Both default to 4 MiB in Ceph, which splits every persist blob above that<br/>into several RADOS objects. persist uploads 8 MiB multipart parts and<br/>writes blobs up to a 128 MiB target, so the stock value turns one blob<br/>write into a dozen or more internal round trips. 16 MiB clears the<br/>multipart part size with room to spare. | `number` | `16777216` | no |
| <a name="input_setup_image"></a> [setup\_image](#input\_setup\_image) | Image used by the bucket-creation Job. Needs an `aws` CLI. | `string` | `"amazon/aws-cli:2.31.19"` | no |
| <a name="input_tolerations"></a> [tolerations](#input\_tolerations) | Tolerations for Ceph daemons, so they can schedule onto a tainted storage node pool. | <pre>list(object({<br/>    key      = string<br/>    operator = string<br/>    value    = optional(string)<br/>    effect   = string<br/>  }))</pre> | `[]` | no |
| <a name="input_use_all_devices"></a> [use\_all\_devices](#input\_use\_all\_devices) | Let Rook consume every unused device on eligible nodes. Only used when `osd_storage_class` is null. | `bool` | `false` | no |
| <a name="input_wait_for_ready"></a> [wait\_for\_ready](#input\_wait\_for\_ready) | Wait for the bucket Job to complete before returning. Ceph takes several minutes to reach HEALTH\_OK on a fresh cluster. | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_access_key"></a> [access\_key](#output\_access\_key) | Access key for the object store user. |
| <a name="output_bucket"></a> [bucket](#output\_bucket) | Bucket created for persist data. |
| <a name="output_credentials_secret_name"></a> [credentials\_secret\_name](#output\_credentials\_secret\_name) | Secret Rook generated for the object store user, with `AccessKey` and `SecretKey` keys. |
| <a name="output_endpoint"></a> [endpoint](#output\_endpoint) | In-cluster S3 endpoint for the RGW gateway. |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace Rook and Ceph run in. |
| <a name="output_node_selector"></a> [node\_selector](#output\_node\_selector) | Node selector the store was pinned with, for co-locating a benchmark client with it. |
| <a name="output_object_store_name"></a> [object\_store\_name](#output\_object\_store\_name) | Name of the CephObjectStore, which is also the suffix of the gateway service. |
| <a name="output_persist_backend_url"></a> [persist\_backend\_url](#output\_persist\_backend\_url) | S3 connection URL for this store, in the form `materialize-instance` expects for `persist_backend_url`. |
| <a name="output_secret_key"></a> [secret\_key](#output\_secret\_key) | Secret key for the object store user. |
| <a name="output_tolerations"></a> [tolerations](#output\_tolerations) | Tolerations the store was given, which a benchmark client needs to share its nodes. |
