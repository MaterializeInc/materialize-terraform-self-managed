## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.8 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 2.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | ~> 2.0 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [kubernetes_deployment.ui](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/deployment) | resource |
| [kubernetes_namespace.ui](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace) | resource |
| [kubernetes_secret.secrets](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret) | resource |
| [kubernetes_service.ui](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service) | resource |
| [random_password.cookie_secret](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.csrf_cookie_secret](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cookie_secret"></a> [cookie\_secret](#input\_cookie\_secret) | Secret for signing cookies. If not set, a random 32-character secret will be generated. | `string` | `null` | no |
| <a name="input_create_namespace"></a> [create\_namespace](#input\_create\_namespace) | Whether to create the Kubernetes namespace. | `bool` | `false` | no |
| <a name="input_csrf_cookie_name"></a> [csrf\_cookie\_name](#input\_csrf\_cookie\_name) | Name of the CSRF cookie. Should be prefixed with \_\_HOST- in production. | `string` | `"__HOST-ory-ui-x-csrf-token"` | no |
| <a name="input_csrf_cookie_secret"></a> [csrf\_cookie\_secret](#input\_csrf\_cookie\_secret) | Secret for CSRF cookie hashing. If not set, a random 32-character secret will be generated. | `string` | `null` | no |
| <a name="input_disable_secure_csrf_cookies"></a> [disable\_secure\_csrf\_cookies](#input\_disable\_secure\_csrf\_cookies) | Disable secure CSRF cookies. Only use in local development without HTTPS. | `bool` | `false` | no |
| <a name="input_extra_env"></a> [extra\_env](#input\_extra\_env) | Additional environment variables as a map of name to value. | `map(string)` | `{}` | no |
| <a name="input_hydra_admin_url"></a> [hydra\_admin\_url](#input\_hydra\_admin\_url) | Internal URL for the Hydra admin API. Example: http://hydra-admin.ory.svc.cluster.local:4445 | `string` | n/a | yes |
| <a name="input_image_pull_policy"></a> [image\_pull\_policy](#input\_image\_pull\_policy) | Image pull policy. | `string` | `"IfNotPresent"` | no |
| <a name="input_image_repository"></a> [image\_repository](#input\_image\_repository) | Docker image repository for the selfservice UI. | `string` | `"oryd/kratos-selfservice-ui-node"` | no |
| <a name="input_image_tag"></a> [image\_tag](#input\_image\_tag) | Docker image tag for the selfservice UI. | `string` | `"v25.4.0"` | no |
| <a name="input_kratos_admin_url"></a> [kratos\_admin\_url](#input\_kratos\_admin\_url) | Internal URL for the Kratos admin API. Example: http://kratos-admin.ory.svc.cluster.local:4434 | `string` | n/a | yes |
| <a name="input_kratos_browser_url"></a> [kratos\_browser\_url](#input\_kratos\_browser\_url) | Browser-accessible URL for the Kratos public API. If not set, kratos\_public\_url is used. | `string` | `null` | no |
| <a name="input_kratos_public_url"></a> [kratos\_public\_url](#input\_kratos\_public\_url) | Internal URL for the Kratos public API. Example: http://kratos-public.ory.svc.cluster.local:4433 | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name for the selfservice UI Kubernetes resources. | `string` | `"ory-selfservice-ui"` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Kubernetes namespace for the Ory selfservice UI. | `string` | `"ory"` | no |
| <a name="input_node_selector"></a> [node\_selector](#input\_node\_selector) | Node selector for selfservice UI pods. | `map(string)` | `{}` | no |
| <a name="input_port"></a> [port](#input\_port) | Port the selfservice UI listens on. | `number` | `3000` | no |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Project name displayed in the UI. | `string` | `"Materialize"` | no |
| <a name="input_replica_count"></a> [replica\_count](#input\_replica\_count) | Number of replicas. | `number` | `2` | no |
| <a name="input_resources"></a> [resources](#input\_resources) | Resource requests and limits for selfservice UI pods. | <pre>object({<br/>    requests = optional(object({<br/>      cpu    = optional(string, "100m")<br/>      memory = optional(string, "128Mi")<br/>    }))<br/>    limits = optional(object({<br/>      cpu    = optional(string)<br/>      memory = optional(string, "128Mi")<br/>    }))<br/>  })</pre> | <pre>{<br/>  "limits": {},<br/>  "requests": {}<br/>}</pre> | no |
| <a name="input_tls_cert_secret_name"></a> [tls\_cert\_secret\_name](#input\_tls\_cert\_secret\_name) | Name of a Kubernetes TLS secret (containing tls.crt and tls.key) to mount into the pod and serve HTTPS from. Typically created by cert-manager. When set, the selfservice UI serves HTTPS directly. | `string` | `null` | no |
| <a name="input_tolerations"></a> [tolerations](#input\_tolerations) | Tolerations for selfservice UI pods. | <pre>list(object({<br/>    key      = string<br/>    value    = optional(string)<br/>    operator = optional(string, "Equal")<br/>    effect   = string<br/>  }))</pre> | `[]` | no |
| <a name="input_trusted_client_ids"></a> [trusted\_client\_ids](#input\_trusted\_client\_ids) | List of OAuth2 client IDs that are trusted and can skip the consent screen. | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace where the selfservice UI is deployed. |
| <a name="output_port"></a> [port](#output\_port) | Port the selfservice UI listens on. |
| <a name="output_service_name"></a> [service\_name](#output\_service\_name) | Name of the Kubernetes Service for the selfservice UI. |
| <a name="output_service_url"></a> [service\_url](#output\_service\_url) | Internal URL of the selfservice UI service. Uses https when TLS is enabled. |
