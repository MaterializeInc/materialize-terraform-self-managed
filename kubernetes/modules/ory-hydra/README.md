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
| [helm_release.hydra](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_namespace.hydra](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace) | resource |
| [random_password.secrets_cookie](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.secrets_system](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_automigration_enabled"></a> [automigration\_enabled](#input\_automigration\_enabled) | Whether to enable automatic database migration. | `bool` | `true` | no |
| <a name="input_automigration_type"></a> [automigration\_type](#input\_automigration\_type) | Type of automigration: 'job' (Helm hook) or 'initContainer'. | `string` | `"job"` | no |
| <a name="input_chart_version"></a> [chart\_version](#input\_chart\_version) | Version of the Ory Hydra Helm chart to install. | `string` | `"0.60.1"` | no |
| <a name="input_consent_url"></a> [consent\_url](#input\_consent\_url) | The URL of the consent UI. Hydra redirects users here for consent. Example: https://login.example.com/consent | `string` | `null` | no |
| <a name="input_cors_allowed_origins"></a> [cors\_allowed\_origins](#input\_cors\_allowed\_origins) | List of origins allowed to make cross-origin requests to Hydra's public API. Required when browser-based OIDC clients (like the Materialize console) are on a different origin. | `list(string)` | `[]` | no |
| <a name="input_create_namespace"></a> [create\_namespace](#input\_create\_namespace) | Whether to create the Kubernetes namespace. Set to false if the namespace already exists. | `bool` | `true` | no |
| <a name="input_dsn"></a> [dsn](#input\_dsn) | PostgreSQL DSN for Hydra database connection. Example: postgres://user:password@host:5432/hydra?sslmode=require | `string` | n/a | yes |
| <a name="input_helm_values"></a> [helm\_values](#input\_helm\_values) | Additional values to pass to the Helm chart. These will be deep-merged with the module's default values, with these values taking precedence. | `any` | `{}` | no |
| <a name="input_image_pull_secrets"></a> [image\_pull\_secrets](#input\_image\_pull\_secrets) | List of Kubernetes secret names for pulling images from private registries. Required for OEL deployments. | `list(string)` | `[]` | no |
| <a name="input_image_repository"></a> [image\_repository](#input\_image\_repository) | Override the Docker image repository for Hydra. Must include the full registry path as the Ory Helm chart ignores image.registry. Example: europe-docker.pkg.dev/ory-artifacts/ory-enterprise/hydra-oel | `string` | `null` | no |
| <a name="input_image_tag"></a> [image\_tag](#input\_image\_tag) | Override the Docker image tag for Hydra. If not set, the chart default will be used. | `string` | `null` | no |
| <a name="input_install_timeout"></a> [install\_timeout](#input\_install\_timeout) | Timeout for installing the Ory Hydra Helm chart, in seconds. | `number` | `600` | no |
| <a name="input_issuer_url"></a> [issuer\_url](#input\_issuer\_url) | The public URL of the OAuth2 issuer. Used for OIDC discovery. Example: https://auth.example.com/ | `string` | n/a | yes |
| <a name="input_login_url"></a> [login\_url](#input\_login\_url) | The URL of the login UI. Hydra redirects users here for authentication. Example: https://login.example.com/login | `string` | `null` | no |
| <a name="input_logout_url"></a> [logout\_url](#input\_logout\_url) | The URL of the logout UI. Example: https://login.example.com/logout | `string` | `null` | no |
| <a name="input_maester_enabled"></a> [maester\_enabled](#input\_maester\_enabled) | Whether to enable hydra-maester (CRD controller for managing OAuth2 clients via Kubernetes resources). | `bool` | `true` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Kubernetes namespace for Ory Hydra. | `string` | `"ory-hydra"` | no |
| <a name="input_node_selector"></a> [node\_selector](#input\_node\_selector) | Node selector for Hydra pods. | `map(string)` | `{}` | no |
| <a name="input_pdb_enabled"></a> [pdb\_enabled](#input\_pdb\_enabled) | Whether to enable PodDisruptionBudget for Hydra. | `bool` | `true` | no |
| <a name="input_pdb_min_available"></a> [pdb\_min\_available](#input\_pdb\_min\_available) | Minimum number of available pods during disruptions. | `number` | `1` | no |
| <a name="input_release_name"></a> [release\_name](#input\_release\_name) | Name of the Helm release. | `string` | `"hydra"` | no |
| <a name="input_replica_count"></a> [replica\_count](#input\_replica\_count) | Number of Hydra replicas. | `number` | `2` | no |
| <a name="input_resources"></a> [resources](#input\_resources) | Resource requests and limits for Hydra pods. By default, CPU has a request but no limit (to allow bursting), and memory request equals memory limit (to avoid OOM issues from overcommit). | <pre>object({<br/>    requests = optional(object({<br/>      cpu    = optional(string, "250m")<br/>      memory = optional(string, "256Mi")<br/>    }))<br/>    limits = optional(object({<br/>      cpu    = optional(string)<br/>      memory = optional(string, "256Mi")<br/>    }))<br/>  })</pre> | <pre>{<br/>  "limits": {},<br/>  "requests": {}<br/>}</pre> | no |
| <a name="input_secrets_cookie"></a> [secrets\_cookie](#input\_secrets\_cookie) | Secret for cookie signing. If not set, a random 32-character secret will be generated. | `string` | `null` | no |
| <a name="input_secrets_system"></a> [secrets\_system](#input\_secrets\_system) | System secret for signing and encryption. Must be at least 16 characters. If not set, a random 32-character secret will be generated. | `string` | `null` | no |
| <a name="input_tls_cert_secret_name"></a> [tls\_cert\_secret\_name](#input\_tls\_cert\_secret\_name) | Name of a Kubernetes TLS secret (containing tls.crt and tls.key) to mount into the Hydra container and serve HTTPS from. Typically created by cert-manager. When set, Hydra's public and admin APIs serve TLS directly. | `string` | `null` | no |
| <a name="input_tolerations"></a> [tolerations](#input\_tolerations) | Tolerations for Hydra pods. | <pre>list(object({<br/>    key      = string<br/>    value    = optional(string)<br/>    operator = optional(string, "Equal")<br/>    effect   = string<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_admin_url"></a> [admin\_url](#output\_admin\_url) | Internal URL for Hydra admin API (privileged: OAuth2 client management, consent/login flow management) |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace where Ory Hydra is deployed |
| <a name="output_public_url"></a> [public\_url](#output\_public\_url) | Internal URL for Hydra public API (user-facing: OAuth2 authorize, token, OIDC discovery) |
| <a name="output_release_name"></a> [release\_name](#output\_release\_name) | Name of the Ory Hydra Helm release |
| <a name="output_release_status"></a> [release\_status](#output\_release\_status) | Status of the Ory Hydra Helm release |
| <a name="output_secrets_cookie"></a> [secrets\_cookie](#output\_secrets\_cookie) | Cookie secret used by Hydra |
| <a name="output_secrets_system"></a> [secrets\_system](#output\_secrets\_system) | System secret used by Hydra |
