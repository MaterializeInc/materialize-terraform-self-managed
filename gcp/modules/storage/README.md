## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 6.31, < 7 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | >= 6.31, < 7 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [google_storage_bucket.materialize](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket) | resource |
| [google_storage_bucket_iam_member.materialize_storage](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_iam_member) | resource |
| [google_storage_hmac_key.materialize](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_hmac_key) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_labels"></a> [labels](#input\_labels) | Labels to apply to resources | `map(string)` | `{}` | no |
| <a name="input_lifecycle_rules"></a> [lifecycle\_rules](#input\_lifecycle\_rules) | List of lifecycle rules to configure | <pre>list(object({<br/>    action = object({<br/>      type          = string<br/>      storage_class = optional(string)<br/>    })<br/>    condition = object({<br/>      age                = optional(number)<br/>      created_before     = optional(string)<br/>      with_state         = optional(string)<br/>      num_newer_versions = optional(number)<br/>    })<br/>  }))</pre> | <pre>[<br/>  {<br/>    "action": {<br/>      "storage_class": "NEARLINE",<br/>      "type": "SetStorageClass"<br/>    },<br/>    "condition": {<br/>      "age": 30<br/>    }<br/>  }<br/>]</pre> | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefix to be used for resource names | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The ID of the project where resources will be created | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | The region where resources will be created | `string` | n/a | yes |
| <a name="input_service_account"></a> [service\_account](#input\_service\_account) | The email of the service account to grant access to the bucket | `string` | n/a | yes |
| <a name="input_version_ttl"></a> [version\_ttl](#input\_version\_ttl) | Sets the TTL (in days) on non current storage bucket objects. This must be set if versioning is turned on. | `number` | `7` | no |
| <a name="input_versioning"></a> [versioning](#input\_versioning) | Enable bucket versioning. This should be enabled for production deployments. | `bool` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_bucket_name"></a> [bucket\_name](#output\_bucket\_name) | The name of the GCS bucket |
| <a name="output_bucket_self_link"></a> [bucket\_self\_link](#output\_bucket\_self\_link) | The self\_link of the GCS bucket |
| <a name="output_bucket_url"></a> [bucket\_url](#output\_bucket\_url) | The URL of the GCS bucket |
| <a name="output_hmac_access_id"></a> [hmac\_access\_id](#output\_hmac\_access\_id) | n/a |
| <a name="output_hmac_secret"></a> [hmac\_secret](#output\_hmac\_secret) | n/a |
