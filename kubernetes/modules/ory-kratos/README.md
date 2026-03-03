## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.8 |
| <a name="requirement_deepmerge"></a> [deepmerge](#requirement\_deepmerge) | ~> 1.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 2.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 2.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_helm"></a> [helm](#provider\_helm) | ~> 2.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | ~> 2.0 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [helm_release.kratos](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_namespace.kratos](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace) | resource |
| [random_password.secrets_cipher](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.secrets_cookie](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.secrets_default](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_automigration_enabled"></a> [automigration\_enabled](#input\_automigration\_enabled) | Whether to enable automatic database migration. | `bool` | `true` | no |
| <a name="input_automigration_type"></a> [automigration\_type](#input\_automigration\_type) | Type of automigration: 'job' (Helm hook) or 'initContainer'. | `string` | `"job"` | no |
| <a name="input_chart_version"></a> [chart\_version](#input\_chart\_version) | Version of the Ory Kratos Helm chart to install. | `string` | `"0.60.1"` | no |
| <a name="input_create_namespace"></a> [create\_namespace](#input\_create\_namespace) | Whether to create the Kubernetes namespace. Set to false if the namespace already exists. | `bool` | `true` | no |
| <a name="input_default_identity_schema_id"></a> [default\_identity\_schema\_id](#input\_default\_identity\_schema\_id) | The default identity schema ID to use. | `string` | `"default"` | no |
| <a name="input_dsn"></a> [dsn](#input\_dsn) | PostgreSQL DSN for Kratos database connection. Example: postgres://user:password@host:5432/kratos?sslmode=require | `string` | n/a | yes |
| <a name="input_helm_values"></a> [helm\_values](#input\_helm\_values) | Additional values to pass to the Helm chart. These will be deep-merged with the module's default values, with these values taking precedence. | `any` | `{}` | no |
| <a name="input_identity_schemas"></a> [identity\_schemas](#input\_identity\_schemas) | Map of identity schema filenames to their JSON content. Example: { "identity.default.schema.json" = file("schemas/default.json") } | `map(string)` | `{}` | no |
| <a name="input_install_timeout"></a> [install\_timeout](#input\_install\_timeout) | Timeout for installing the Ory Kratos Helm chart, in seconds. | `number` | `600` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Kubernetes namespace for Ory Kratos. | `string` | `"ory-kratos"` | no |
| <a name="input_node_selector"></a> [node\_selector](#input\_node\_selector) | Node selector for Kratos pods. | `map(string)` | `{}` | no |
| <a name="input_pdb_enabled"></a> [pdb\_enabled](#input\_pdb\_enabled) | Whether to enable PodDisruptionBudget for Kratos. | `bool` | `true` | no |
| <a name="input_pdb_min_available"></a> [pdb\_min\_available](#input\_pdb\_min\_available) | Minimum number of available pods during disruptions. | `number` | `1` | no |
| <a name="input_release_name"></a> [release\_name](#input\_release\_name) | Name of the Helm release. | `string` | `"kratos"` | no |
| <a name="input_replica_count"></a> [replica\_count](#input\_replica\_count) | Number of Kratos replicas. | `number` | `2` | no |
| <a name="input_resources"></a> [resources](#input\_resources) | Resource requests and limits for Kratos pods. | <pre>object({<br/>    requests = optional(object({<br/>      cpu    = optional(string, "250m")<br/>      memory = optional(string, "256Mi")<br/>    }))<br/>    limits = optional(object({<br/>      cpu    = optional(string, "500m")<br/>      memory = optional(string, "512Mi")<br/>    }))<br/>  })</pre> | <pre>{<br/>  "limits": {},<br/>  "requests": {}<br/>}</pre> | no |
| <a name="input_secrets_cipher"></a> [secrets\_cipher](#input\_secrets\_cipher) | Secret for cipher encryption. If not set, a random 32-character secret will be generated. | `string` | `null` | no |
| <a name="input_secrets_cookie"></a> [secrets\_cookie](#input\_secrets\_cookie) | Secret for cookie signing. If not set, a random 32-character secret will be generated. | `string` | `null` | no |
| <a name="input_secrets_default"></a> [secrets\_default](#input\_secrets\_default) | Default secret for signing and encryption. If not set, a random 32-character secret will be generated. | `string` | `null` | no |
| <a name="input_smtp_connection_uri"></a> [smtp\_connection\_uri](#input\_smtp\_connection\_uri) | SMTP connection URI for sending emails. Example: smtp://user:password@smtp.example.com:587/ | `string` | `""` | no |
| <a name="input_smtp_from_address"></a> [smtp\_from\_address](#input\_smtp\_from\_address) | Email address used as the sender for Kratos emails. | `string` | `""` | no |
| <a name="input_smtp_from_name"></a> [smtp\_from\_name](#input\_smtp\_from\_name) | Name used as the sender for Kratos emails. | `string` | `""` | no |
| <a name="input_tolerations"></a> [tolerations](#input\_tolerations) | Tolerations for Kratos pods. | <pre>list(object({<br/>    key      = string<br/>    value    = optional(string)<br/>    operator = optional(string, "Equal")<br/>    effect   = string<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_admin_url"></a> [admin\_url](#output\_admin\_url) | Internal URL for Kratos admin API |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace where Ory Kratos is deployed |
| <a name="output_public_url"></a> [public\_url](#output\_public\_url) | Internal URL for Kratos public API |
| <a name="output_release_name"></a> [release\_name](#output\_release\_name) | Name of the Ory Kratos Helm release |
| <a name="output_release_status"></a> [release\_status](#output\_release\_status) | Status of the Ory Kratos Helm release |
| <a name="output_secrets_cipher"></a> [secrets\_cipher](#output\_secrets\_cipher) | Cipher secret used by Kratos |
| <a name="output_secrets_cookie"></a> [secrets\_cookie](#output\_secrets\_cookie) | Cookie secret used by Kratos |
| <a name="output_secrets_default"></a> [secrets\_default](#output\_secrets\_default) | Default secret used by Kratos |
