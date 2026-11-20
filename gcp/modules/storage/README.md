## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 8.0, < 9 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_google"></a> [google](#provider\_google) | >= 8.0, < 9 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [google_service_account.persist](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_service_account_iam_member.persist_workload_identity](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_member) | resource |
| [google_storage_bucket.materialize](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket) | resource |
| [google_storage_bucket_iam_member.materialize_storage](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_iam_member) | resource |
| [google_storage_bucket_iam_member.persist](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_iam_member) | resource |
| [google_storage_hmac_key.materialize](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_hmac_key) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_create_hmac_key"></a> [create\_hmac\_key](#input\_create\_hmac\_key) | Create an HMAC key for service\_account, for an S3-compatible persist URL (`s3://<access id>:<secret>@<bucket>/<prefix>?endpoint=https://storage.googleapis.com`). Set false when Materialize reads the bucket natively (`gcs://`, Materialize v26.48.0 and later) through workload\_identity, so no static key exists. | `bool` | `true` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels to apply to resources | `map(string)` | `{}` | no |
| <a name="input_lifecycle_rules"></a> [lifecycle\_rules](#input\_lifecycle\_rules) | List of lifecycle rules to configure | <pre>list(object({<br/>    action = object({<br/>      type          = string<br/>      storage_class = optional(string)<br/>    })<br/>    condition = object({<br/>      age                        = optional(number)<br/>      created_before             = optional(string)<br/>      with_state                 = optional(string)<br/>      num_newer_versions         = optional(number)<br/>      days_since_noncurrent_time = optional(number)<br/>    })<br/>  }))</pre> | <pre>[<br/>  {<br/>    "action": {<br/>      "type": "AbortIncompleteMultipartUpload"<br/>    },<br/>    "condition": {<br/>      "age": 1<br/>    }<br/>  }<br/>]</pre> | no |
| <a name="input_persist_path"></a> [persist\_path](#input\_persist\_path) | Path within the bucket that persist\_backend\_url points at. | `string` | `"materialize"` | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefix to be used for resource names | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The ID of the project where resources will be created | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | The region where resources will be created | `string` | n/a | yes |
| <a name="input_service_account"></a> [service\_account](#input\_service\_account) | Email of the service account the HMAC key belongs to, granted roles/storage.admin on the bucket. Required when create\_hmac\_key is true, and unused when it is false; Materialize then reads the bucket natively through workload\_identity. | `string` | `null` | no |
| <a name="input_version_ttl"></a> [version\_ttl](#input\_version\_ttl) | Delete noncurrent object versions after this many days. Null disables the rule. | `number` | `7` | no |
| <a name="input_versioning"></a> [versioning](#input\_versioning) | Enable bucket versioning. This should be enabled for production deployments. | `bool` | `true` | no |
| <a name="input_workload_identity"></a> [workload\_identity](#input\_workload\_identity) | The Kubernetes service account Materialize's environmentd and clusterd pods run as, so they read and write the bucket natively (`gcs://`, Materialize v26.48.0 and later) through GKE Workload Identity. The operator names it after the Materialize resource, in the instance namespace. When set, the module creates a Google service account with roles/storage.objectAdmin on the bucket and lets that Kubernetes service account impersonate it. Annotate the instance's service account with the workload\_identity\_service\_account\_email output. | <pre>object({<br/>    namespace            = string<br/>    service_account_name = string<br/>  })</pre> | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bucket_name"></a> [bucket\_name](#output\_bucket\_name) | The name of the GCS bucket |
| <a name="output_bucket_self_link"></a> [bucket\_self\_link](#output\_bucket\_self\_link) | The self\_link of the GCS bucket |
| <a name="output_bucket_url"></a> [bucket\_url](#output\_bucket\_url) | The URL of the GCS bucket |
| <a name="output_hmac_access_id"></a> [hmac\_access\_id](#output\_hmac\_access\_id) | Access ID of the HMAC key, or null when create\_hmac\_key is false |
| <a name="output_hmac_secret"></a> [hmac\_secret](#output\_hmac\_secret) | Secret of the HMAC key, or null when create\_hmac\_key is false |
| <a name="output_persist_backend_url"></a> [persist\_backend\_url](#output\_persist\_backend\_url) | Native persist URL (gcs://<bucket>/<persist\_path>), or null when workload\_identity is unset |
| <a name="output_workload_identity_service_account_email"></a> [workload\_identity\_service\_account\_email](#output\_workload\_identity\_service\_account\_email) | Google service account the instance's Kubernetes service account impersonates for native access, or null when workload\_identity is unset. Set it as the instance's iam.gke.io/gcp-service-account annotation. |
