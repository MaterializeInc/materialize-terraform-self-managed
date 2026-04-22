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
| [kubernetes_deployment.polis](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/deployment) | resource |
| [kubernetes_namespace.polis](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace) | resource |
| [kubernetes_secret.polis](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret) | resource |
| [kubernetes_service.polis](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service) | resource |
| [random_password.admin_api_keys](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.nextauth_secret](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_admin_api_keys"></a> [admin\_api\_keys](#input\_admin\_api\_keys) | API key(s) for authenticating requests to Polis admin APIs (injected into the container as the JACKSON\_API\_KEYS env var that upstream Polis expects). If not set, a random 32-character key will be generated. | `string` | `null` | no |
| <a name="input_create_namespace"></a> [create\_namespace](#input\_create\_namespace) | Whether to create the Kubernetes namespace. Set to false if the namespace already exists. | `bool` | `true` | no |
| <a name="input_dsn"></a> [dsn](#input\_dsn) | PostgreSQL DSN for Polis database connection. Example: postgres://user:password@host:5432/polis?sslmode=require | `string` | n/a | yes |
| <a name="input_external_url"></a> [external\_url](#input\_external\_url) | Externally-reachable HTTPS URL for Polis. Used as the SAML ACS URL, OAuth callback base, and NextAuth URL, so it must resolve from end-user browsers. Polis does not serve TLS itself — terminate HTTPS at an ingress or LoadBalancer in front of the pod. Example: https://polis.internal.example.com | `string` | n/a | yes |
| <a name="input_extra_env"></a> [extra\_env](#input\_extra\_env) | Additional environment variables for Polis pods as a map of name to value. | `map(string)` | `{}` | no |
| <a name="input_image_pull_policy"></a> [image\_pull\_policy](#input\_image\_pull\_policy) | Image pull policy for Polis pods. | `string` | `"IfNotPresent"` | no |
| <a name="input_image_pull_secrets"></a> [image\_pull\_secrets](#input\_image\_pull\_secrets) | List of Kubernetes secret names for pulling images from private registries. Required for OEL deployments. | `list(string)` | `[]` | no |
| <a name="input_image_registry"></a> [image\_registry](#input\_image\_registry) | Docker image registry for Polis. Example: europe-docker.pkg.dev | `string` | `"docker.io"` | no |
| <a name="input_image_repository"></a> [image\_repository](#input\_image\_repository) | Docker image repository for Polis. Example: ory-artifacts/ory-enterprise-polis/polis-oel | `string` | `"boxyhq/jackson"` | no |
| <a name="input_image_tag"></a> [image\_tag](#input\_image\_tag) | Docker image tag for Polis. | `string` | `"1.52.2"` | no |
| <a name="input_name"></a> [name](#input\_name) | Name prefix for Polis Kubernetes resources. | `string` | `"polis"` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Kubernetes namespace for Ory Polis. | `string` | `"ory-polis"` | no |
| <a name="input_nextauth_secret"></a> [nextauth\_secret](#input\_nextauth\_secret) | Secret for NextAuth.js session signing. If not set, a random 32-character secret will be generated. | `string` | `null` | no |
| <a name="input_node_selector"></a> [node\_selector](#input\_node\_selector) | Node selector for Polis pods. | `map(string)` | `{}` | no |
| <a name="input_port"></a> [port](#input\_port) | Port that the Polis application listens on. | `number` | `5225` | no |
| <a name="input_replica_count"></a> [replica\_count](#input\_replica\_count) | Number of Polis replicas. | `number` | `2` | no |
| <a name="input_resources"></a> [resources](#input\_resources) | Resource requests and limits for Polis pods. | <pre>object({<br/>    requests = optional(object({<br/>      cpu    = optional(string, "250m")<br/>      memory = optional(string, "512Mi")<br/>    }))<br/>    limits = optional(object({<br/>      cpu    = optional(string)<br/>      memory = optional(string, "512Mi")<br/>    }))<br/>  })</pre> | <pre>{<br/>  "limits": {},<br/>  "requests": {}<br/>}</pre> | no |
| <a name="input_saml_audience"></a> [saml\_audience](#input\_saml\_audience) | SAML audience identifier (Polis's SAML entity ID). Identity providers validate that SAML assertions are intended for this audience. Must match the audience configured on the upstream IdP. Example: https://saml.example.com/entityid | `string` | n/a | yes |
| <a name="input_tolerations"></a> [tolerations](#input\_tolerations) | Tolerations for Polis pods. | <pre>list(object({<br/>    key      = string<br/>    value    = optional(string)<br/>    operator = optional(string, "Equal")<br/>    effect   = string<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_admin_api_keys"></a> [admin\_api\_keys](#output\_admin\_api\_keys) | API key for Polis admin APIs |
| <a name="output_external_url"></a> [external\_url](#output\_external\_url) | Externally-reachable HTTPS URL for Polis, as supplied via var.external\_url. This is the browser-facing URL that SAML/OAuth flows redirect through, and the issuer URL that upstream OIDC consumers (e.g., Kratos social sign-in) should point at. |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace where Ory Polis is deployed |
| <a name="output_nextauth_secret"></a> [nextauth\_secret](#output\_nextauth\_secret) | NextAuth.js session signing secret |
| <a name="output_url"></a> [url](#output\_url) | Internal cluster URL for Polis (SSO, SCIM, OAuth endpoints). Always http because Polis does not serve TLS itself — TLS is terminated externally in front of the pod. |
