## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.10.0, < 2.39.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.1, < 3.10.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | >= 2.10.0, < 2.39.0 |
| <a name="provider_random"></a> [random](#provider\_random) | ~> 3.1, < 3.10.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [kubernetes_job.create_bucket](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/job) | resource |
| [kubernetes_namespace.this](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace) | resource |
| [kubernetes_secret.credentials](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret) | resource |
| [kubernetes_service.headless](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service) | resource |
| [kubernetes_service.this](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service) | resource |
| [kubernetes_stateful_set.this](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/stateful_set) | resource |
| [random_password.secret_key](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_access_key"></a> [access\_key](#input\_access\_key) | RustFS root access key. | `string` | `"rustfsadmin"` | no |
| <a name="input_bucket"></a> [bucket](#input\_bucket) | Bucket created for Materialize's persist data. | `string` | `"materialize"` | no |
| <a name="input_create_namespace"></a> [create\_namespace](#input\_create\_namespace) | Whether to create the namespace. Set false when another module already owns it. | `bool` | `true` | no |
| <a name="input_drive_size"></a> [drive\_size](#input\_drive\_size) | Size of each data volume. | `string` | `"100Gi"` | no |
| <a name="input_drives_per_replica"></a> [drives\_per\_replica](#input\_drives\_per\_replica) | Number of data volumes mounted per pod.<br/><br/>Storage-optimized instances expose several local NVMe devices, and RustFS<br/>erasure-codes across drives as well as across pods. Each drive gets its own<br/>PersistentVolumeClaim from `storage_class`. | `number` | `1` | no |
| <a name="input_image"></a> [image](#input\_image) | RustFS server image. | `string` | `"rustfs/rustfs:1.0.0-rc.5"` | no |
| <a name="input_name"></a> [name](#input\_name) | Name for the RustFS release, used for the StatefulSet, services and labels. | `string` | `"rustfs"` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace to deploy RustFS into. | `string` | `"object-store"` | no |
| <a name="input_node_selector"></a> [node\_selector](#input\_node\_selector) | Node selector for RustFS pods. Use this to pin the store to a storage-optimized node pool. | `map(string)` | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | Region reported to S3 clients. RustFS ignores it, but the AWS SDKs require one to sign requests. | `string` | `"us-east-1"` | no |
| <a name="input_replicas"></a> [replicas](#input\_replicas) | Number of RustFS server pods.<br/><br/>One replica runs a single-node store against a single drive. More than one<br/>replica forms an erasure-coded set across the pods, which needs<br/>`replicas * drives_per_replica` to be at least 4. Use an odd count only if<br/>you know RustFS accepts the resulting set size. | `number` | `1` | no |
| <a name="input_resources"></a> [resources](#input\_resources) | Resource requests and limits for the RustFS containers. | <pre>object({<br/>    requests = optional(map(string), { cpu = "100m", memory = "256Mi" })<br/>    limits   = optional(map(string), {})<br/>  })</pre> | `{}` | no |
| <a name="input_secret_key"></a> [secret\_key](#input\_secret\_key) | RustFS root secret key. Null generates one.<br/><br/>This is a test and benchmarking backend, so the generated value lands in<br/>Terraform state like any other generated credential. | `string` | `null` | no |
| <a name="input_setup_image"></a> [setup\_image](#input\_setup\_image) | Image used by the bucket-creation Job. Needs an `aws` CLI. | `string` | `"amazon/aws-cli:2.31.19"` | no |
| <a name="input_storage_class"></a> [storage\_class](#input\_storage\_class) | StorageClass for the data volumes. Null uses the cluster default.<br/><br/>For benchmarking, point this at a class backed by the node's local NVMe<br/>rather than network storage, or the numbers measure the network. | `string` | `null` | no |
| <a name="input_tolerations"></a> [tolerations](#input\_tolerations) | Tolerations for RustFS pods, so they can schedule onto a tainted storage node pool. | <pre>list(object({<br/>    key      = string<br/>    operator = string<br/>    value    = optional(string)<br/>    effect   = string<br/>  }))</pre> | `[]` | no |
| <a name="input_wait_for_ready"></a> [wait\_for\_ready](#input\_wait\_for\_ready) | Wait for the StatefulSet to report ready before returning. Disable for faster plans in CI. | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_access_key"></a> [access\_key](#output\_access\_key) | Root access key for the store. |
| <a name="output_bucket"></a> [bucket](#output\_bucket) | Bucket created for persist data. |
| <a name="output_credentials_secret_name"></a> [credentials\_secret\_name](#output\_credentials\_secret\_name) | Secret holding the store's root credentials, with `access_key` and `secret_key` keys. |
| <a name="output_drive_count"></a> [drive\_count](#output\_drive\_count) | Total number of drives in the store, which is what RustFS erasure-codes across. |
| <a name="output_endpoint"></a> [endpoint](#output\_endpoint) | In-cluster S3 endpoint for the store. |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace the store runs in. |
| <a name="output_node_selector"></a> [node\_selector](#output\_node\_selector) | Node selector the store was pinned with, for co-locating a benchmark client with it. |
| <a name="output_persist_backend_url"></a> [persist\_backend\_url](#output\_persist\_backend\_url) | S3 connection URL for this store, in the form `materialize-instance` expects for `persist_backend_url`. |
| <a name="output_secret_key"></a> [secret\_key](#output\_secret\_key) | Root secret key for the store. |
| <a name="output_service_name"></a> [service\_name](#output\_service\_name) | Name of the ClusterIP service clients should connect to. |
| <a name="output_tolerations"></a> [tolerations](#output\_tolerations) | Tolerations the store was given, which a benchmark client needs to share its nodes. |
