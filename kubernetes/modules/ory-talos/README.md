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
| [kubernetes_deployment.talos](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/deployment) | resource |
| [kubernetes_namespace.talos](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace) | resource |
| [kubernetes_secret.talos](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret) | resource |
| [kubernetes_service.talos](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service) | resource |
| [random_password.default_secret](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.hmac_secret](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.pagination_secret](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_create_namespace"></a> [create\_namespace](#input\_create\_namespace) | Whether to create the Kubernetes namespace. Set to false if the namespace already exists. | `bool` | `true` | no |
| <a name="input_credentials_issuer"></a> [credentials\_issuer](#input\_credentials\_issuer) | Issuer claim Talos puts in derived JWTs. Maps to TALOS\_CREDENTIALS\_ISSUER. Must match what downstream services (e.g., Materialize) validate as the OIDC issuer. For Hydra coexistence (so a single downstream can trust both), set this to the same URL Hydra publishes as its issuer and have both services share signing keys via var.signing\_keys\_urls. Example: https://auth.internal.example.com | `string` | n/a | yes |
| <a name="input_default_secret"></a> [default\_secret](#input\_default\_secret) | Secret used by Talos default components, set as TALOS\_SECRETS\_DEFAULT\_CURRENT. Must be at least 32 characters. If null, a random 32-character secret is generated. | `string` | `null` | no |
| <a name="input_dsn"></a> [dsn](#input\_dsn) | PostgreSQL DSN for Talos. Maps to the TALOS\_DB\_DSN env var. Example: postgres://user:password@host:5432/talos?sslmode=require | `string` | n/a | yes |
| <a name="input_extra_env"></a> [extra\_env](#input\_extra\_env) | Additional environment variables for Talos as a map of name to value. Useful for any TALOS\_* config not yet wired through a dedicated variable (e.g., cache, rate-limit, tracing, all of which are commercial features in Talos). | `map(string)` | `{}` | no |
| <a name="input_hmac_secret"></a> [hmac\_secret](#input\_hmac\_secret) | HMAC secret used by Talos for API key generation, set as TALOS\_SECRETS\_HMAC\_CURRENT. Must be at least 32 characters. If null, a random 32-character secret is generated. | `string` | `null` | no |
| <a name="input_http_port"></a> [http\_port](#input\_http\_port) | Port that Talos's HTTP API listens on (TALOS\_SERVE\_HTTP\_PORT). Default matches the Talos config schema. | `number` | `4420` | no |
| <a name="input_image_pull_policy"></a> [image\_pull\_policy](#input\_image\_pull\_policy) | Image pull policy for Talos pods. | `string` | `"IfNotPresent"` | no |
| <a name="input_image_pull_secrets"></a> [image\_pull\_secrets](#input\_image\_pull\_secrets) | List of Kubernetes secret names (in the Talos namespace) used to pull the OEL image. During early access, the Talos image is gated by a separate service-account key from the rest of OEL; pass the secret name backing that key here. | `list(string)` | `[]` | no |
| <a name="input_image_registry"></a> [image\_registry](#input\_image\_registry) | Docker image registry for the Talos OEL container. Mirrors the registry layout used by other Ory OEL components. | `string` | `"europe-docker.pkg.dev"` | no |
| <a name="input_image_repository"></a> [image\_repository](#input\_image\_repository) | Docker image repository for the Talos OEL container. Default follows the Ory enterprise naming convention; override for mirrored / air-gapped registries. | `string` | `"ory-artifacts/ory-enterprise-talos/talos-oel"` | no |
| <a name="input_image_tag"></a> [image\_tag](#input\_image\_tag) | Docker image tag for the Talos OEL container. Pin a specific version in production; 'latest' is the default for early-access exploration. | `string` | `"latest"` | no |
| <a name="input_log_format"></a> [log\_format](#input\_log\_format) | TALOS\_LOG\_FORMAT. One of json or text. | `string` | `"json"` | no |
| <a name="input_log_level"></a> [log\_level](#input\_log\_level) | TALOS\_LOG\_LEVEL. One of debug, info, warn, error. | `string` | `"info"` | no |
| <a name="input_metrics_port"></a> [metrics\_port](#input\_metrics\_port) | Port that Talos's metrics endpoint listens on (TALOS\_SERVE\_METRICS\_PORT). Commercial feature; defaults to 4422 to match Talos's default. | `number` | `4422` | no |
| <a name="input_name"></a> [name](#input\_name) | Name prefix for Talos Kubernetes resources. | `string` | `"talos"` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Kubernetes namespace for Ory Talos. | `string` | `"ory-talos"` | no |
| <a name="input_node_selector"></a> [node\_selector](#input\_node\_selector) | Node selector for Talos pods. | `map(string)` | `{}` | no |
| <a name="input_pagination_secret"></a> [pagination\_secret](#input\_pagination\_secret) | Secret used for signing pagination tokens, set as TALOS\_SECRETS\_PAGINATION\_CURRENT. Must be at least 32 characters. If null, a random 32-character secret is generated. | `string` | `null` | no |
| <a name="input_replica_count"></a> [replica\_count](#input\_replica\_count) | Number of Talos replicas. | `number` | `2` | no |
| <a name="input_resources"></a> [resources](#input\_resources) | Resource requests and limits for Talos pods. | <pre>object({<br/>    requests = optional(object({<br/>      cpu    = optional(string, "100m")<br/>      memory = optional(string, "256Mi")<br/>    }))<br/>    limits = optional(object({<br/>      cpu    = optional(string)<br/>      memory = optional(string, "256Mi")<br/>    }))<br/>  })</pre> | <pre>{<br/>  "limits": {},<br/>  "requests": {}<br/>}</pre> | no |
| <a name="input_signing_key_id"></a> [signing\_key\_id](#input\_signing\_key\_id) | Optional hint pointing Talos at a specific JWK to sign derived tokens with. Maps to TALOS\_CREDENTIALS\_DERIVED\_TOKENS\_JWT\_SIGNING\_KEY\_ID. Use together with var.signing\_keys\_urls when sharing keys with another issuer (e.g., Hydra). | `string` | `null` | no |
| <a name="input_signing_keys_urls"></a> [signing\_keys\_urls](#input\_signing\_keys\_urls) | Optional list of JWKS URLs Talos pulls signing keys from. Maps to TALOS\_CREDENTIALS\_DERIVED\_TOKENS\_JWT\_SIGNING\_KEYS\_URLS. The Hydra-coexistence pattern: point this at Hydra's JWKS so both services sign derived tokens with the same key set, then a downstream validating one issuer URL accepts JWTs from either. | `list(string)` | `[]` | no |
| <a name="input_tolerations"></a> [tolerations](#input\_tolerations) | Tolerations for Talos pods. | <pre>list(object({<br/>    key      = string<br/>    value    = optional(string)<br/>    operator = optional(string, "Equal")<br/>    effect   = string<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_credentials_issuer"></a> [credentials\_issuer](#output\_credentials\_issuer) | Issuer claim Talos uses in derived JWTs. Wire this into downstream OIDC consumers (e.g., Materialize's oidc\_issuer) so they validate Talos-issued tokens. |
| <a name="output_default_secret"></a> [default\_secret](#output\_default\_secret) | Talos default-component secret. |
| <a name="output_hmac_secret"></a> [hmac\_secret](#output\_hmac\_secret) | Talos HMAC secret used for API key generation. |
| <a name="output_internal_url"></a> [internal\_url](#output\_internal\_url) | Internal cluster URL for Talos. Both the admin plane (key issuance / rotation / revocation) and the data plane (verify, batchVerify, selfRevoke) share this base URL. The admin plane has no built-in auth and must stay cluster-internal; only the verify and self-revoke endpoints are safe to expose externally. |
| <a name="output_metrics_url"></a> [metrics\_url](#output\_metrics\_url) | Internal URL for the Talos metrics endpoint. Commercial feature. |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace where Talos is deployed. |
| <a name="output_pagination_secret"></a> [pagination\_secret](#output\_pagination\_secret) | Talos pagination-token signing secret. |
| <a name="output_service_name"></a> [service\_name](#output\_service\_name) | Kubernetes service name for Talos. |
