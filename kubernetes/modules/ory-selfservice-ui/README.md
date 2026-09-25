## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 2.0, < 2.39.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.0.0, < 3.10.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | ~> 2.0, < 2.39.0 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.0.0, < 3.10.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [kubernetes_deployment.ui](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/deployment) | resource |
| [kubernetes_namespace.ui](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace) | resource |
| [kubernetes_secret.secrets](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret) | resource |
| [kubernetes_service.ui](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service) | resource |
| [random_password.cookie_secret](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.csrf_cookie_secret](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.token_hook_api_key](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_claim_traits_access_token"></a> [claim\_traits\_access\_token](#input\_claim\_traits\_access\_token) | Identity trait names copied from the Kratos identity onto every access token issued through the consent flow. Materialize reads groups off the access token, which is what makes MCP OAuth work. | `list(string)` | <pre>[<br/>  "groups"<br/>]</pre> | no |
| <a name="input_claim_traits_id_token"></a> [claim\_traits\_id\_token](#input\_claim\_traits\_id\_token) | Identity trait names copied from the Kratos identity onto every id\_token issued through the consent flow. Pairs with Hydra's allowed\_top\_level\_claims so the claims land top-level rather than under Hydra's ext. | `list(string)` | <pre>[<br/>  "groups"<br/>]</pre> | no |
| <a name="input_cookie_secret"></a> [cookie\_secret](#input\_cookie\_secret) | Secret for signing cookies. Must be at least 32 characters. If not set, a random 32-character secret will be generated. | `string` | `null` | no |
| <a name="input_create_namespace"></a> [create\_namespace](#input\_create\_namespace) | Whether to create the Kubernetes namespace. | `bool` | `false` | no |
| <a name="input_csrf_cookie_name"></a> [csrf\_cookie\_name](#input\_csrf\_cookie\_name) | Name of the CSRF cookie. Should be prefixed with \_\_HOST- in production. | `string` | `"__HOST-ory-ui-x-csrf-token"` | no |
| <a name="input_csrf_cookie_secret"></a> [csrf\_cookie\_secret](#input\_csrf\_cookie\_secret) | Secret for CSRF cookie hashing. Must be at least 32 characters. If not set, a random 32-character secret will be generated. | `string` | `null` | no |
| <a name="input_dcr_audience_allowlist"></a> [dcr\_audience\_allowlist](#input\_dcr\_audience\_allowlist) | https URIs (DCR\_AUDIENCE\_ALLOWLIST). A client with no registered audience, typically an MCP client that registered itself through Hydra's dynamic client registration, that asks for an RFC 8707 resource under one of these entries is granted that entry as its access token audience, and the entry is written onto the client so refresh keeps working. Set it to the Materialize MCP resource URL(s), which must also be in Materialize's oidc\_audience. | `list(string)` | `[]` | no |
| <a name="input_dcr_default_audience"></a> [dcr\_default\_audience](#input\_dcr\_default\_audience) | https URIs (DCR\_DEFAULT\_AUDIENCE) granted to a client that has no registered audience and requested no resource. Same rules as dcr\_audience\_allowlist. Empty leaves such clients without an audience, which Materialize rejects. | `list(string)` | `[]` | no |
| <a name="input_disable_secure_csrf_cookies"></a> [disable\_secure\_csrf\_cookies](#input\_disable\_secure\_csrf\_cookies) | Disable secure CSRF cookies. Only use in local development without HTTPS. | `bool` | `false` | no |
| <a name="input_extra_env"></a> [extra\_env](#input\_extra\_env) | Additional environment variables as a map of name to value. | `map(string)` | `{}` | no |
| <a name="input_hydra_admin_url"></a> [hydra\_admin\_url](#input\_hydra\_admin\_url) | Internal URL for the Hydra admin API. Example: http://hydra-admin.ory.svc.cluster.local:4445 | `string` | n/a | yes |
| <a name="input_image_pull_policy"></a> [image\_pull\_policy](#input\_image\_pull\_policy) | Image pull policy. | `string` | `"IfNotPresent"` | no |
| <a name="input_image_repository"></a> [image\_repository](#input\_image\_repository) | Docker image repository for the selfservice UI. Defaults to Materialize's own ory-selfservice service (https://github.com/MaterializeInc/ory-selfservice), published publicly on Docker Hub. Air-gapped installs mirror the image into their own registry and point this at the mirror. | `string` | `"materialize/ory-selfservice"` | no |
| <a name="input_image_tag"></a> [image\_tag](#input\_image\_tag) | Docker image tag for the selfservice UI. Tracks ory-selfservice releases; pin it (rather than following a floating tag) so upgrades are deliberate, and mirror the same tag for air-gapped installs. | `string` | `"v0.2.1"` | no |
| <a name="input_kratos_admin_url"></a> [kratos\_admin\_url](#input\_kratos\_admin\_url) | Internal URL for the Kratos admin API. Example: http://kratos-admin.ory.svc.cluster.local:4434 | `string` | n/a | yes |
| <a name="input_kratos_browser_url"></a> [kratos\_browser\_url](#input\_kratos\_browser\_url) | Browser-accessible URL for the Kratos public API. If not set, kratos\_public\_url is used. Unused when screens\_enabled is false, since the browser never reaches the self-service screens. | `string` | `null` | no |
| <a name="input_kratos_cookie_domain"></a> [kratos\_cookie\_domain](#input\_kratos\_cookie\_domain) | Parent domain shared by the UI's hostname and the Kratos browser host (KRATOS\_COOKIE\_DOMAIN), e.g. example.com. Set it to Kratos's cookies.domain whenever the two are on different hostnames: Kratos sets its SSO continuity cookie without a Domain, and without this the cookie stays on the UI's host, so the OIDC/SAML callback to Kratos fails with "no resumable session found". Null leaves such cookies host-only. Unused when screens\_enabled is false. | `string` | `null` | no |
| <a name="input_kratos_public_url"></a> [kratos\_public\_url](#input\_kratos\_public\_url) | Internal URL for the Kratos public API. Example: http://kratos-public.ory.svc.cluster.local:4433. Required when screens\_enabled is true; consent-only deployments (screens\_enabled = false) never talk to the Kratos public API and can leave it null. | `string` | `null` | no |
| <a name="input_log_level"></a> [log\_level](#input\_log\_level) | Log level for the selfservice service. | `string` | `"info"` | no |
| <a name="input_log_redact_pii"></a> [log\_redact\_pii](#input\_log\_redact\_pii) | Redact personally identifiable information (email addresses, trait values) from the service's logs. Leave false while debugging sign-in issues; turn it on where logs are shipped off-cluster. | `bool` | `false` | no |
| <a name="input_metrics_port"></a> [metrics\_port](#input\_metrics\_port) | Port for the service's Prometheus metrics listener (METRICS\_PORT). Served separately from the public port so the LoadBalancer never exposes it; scrape it from the pod. Null disables the listener. Must differ from var.port. | `number` | `null` | no |
| <a name="input_name"></a> [name](#input\_name) | Name for the selfservice UI Kubernetes resources. | `string` | `"ory-selfservice-ui"` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Kubernetes namespace for the Ory selfservice UI. | `string` | `"ory"` | no |
| <a name="input_node_selector"></a> [node\_selector](#input\_node\_selector) | Node selector for selfservice UI pods. | `map(string)` | `{}` | no |
| <a name="input_port"></a> [port](#input\_port) | Port the selfservice UI listens on. | `number` | `3000` | no |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Project name displayed in the UI. | `string` | `"Materialize"` | no |
| <a name="input_remember_consent_for_seconds"></a> [remember\_consent\_for\_seconds](#input\_remember\_consent\_for\_seconds) | How long Hydra remembers a granted consent for, in seconds. Within this window returning users skip the consent screen. | `number` | `3600` | no |
| <a name="input_replica_count"></a> [replica\_count](#input\_replica\_count) | Number of replicas. | `number` | `2` | no |
| <a name="input_resources"></a> [resources](#input\_resources) | Resource requests and limits for selfservice UI pods. | <pre>object({<br/>    requests = optional(object({<br/>      cpu    = optional(string, "100m")<br/>      memory = optional(string, "128Mi")<br/>    }))<br/>    limits = optional(object({<br/>      cpu    = optional(string)<br/>      memory = optional(string, "128Mi")<br/>    }))<br/>  })</pre> | <pre>{<br/>  "limits": {},<br/>  "requests": {}<br/>}</pre> | no |
| <a name="input_screens_enabled"></a> [screens\_enabled](#input\_screens\_enabled) | Serve the Kratos self-service screens (login, registration, recovery, verification, settings, error). Set to false for consent-only mode, where the service only serves Hydra's consent endpoint, the health endpoints and (when enabled) the token hook, and another app - typically the Materialize console - owns the user-facing flows. In that mode kratos\_public\_url and kratos\_browser\_url are unused. | `bool` | `true` | no |
| <a name="input_screens_recovery_enabled"></a> [screens\_recovery\_enabled](#input\_screens\_recovery\_enabled) | Whether the login screen offers account recovery (SCREENS\_RECOVERY\_ENABLED). Set to match Kratos's selfservice.flows.recovery.enabled. | `bool` | `true` | no |
| <a name="input_screens_registration_enabled"></a> [screens\_registration\_enabled](#input\_screens\_registration\_enabled) | Whether the login screen links to registration (SCREENS\_REGISTRATION\_ENABLED). Set to match Kratos's selfservice.flows.registration.enabled; the link otherwise leads to a flow Kratos refuses. | `bool` | `true` | no |
| <a name="input_screens_verification_enabled"></a> [screens\_verification\_enabled](#input\_screens\_verification\_enabled) | Whether the screens link to address verification (SCREENS\_VERIFICATION\_ENABLED). Set to match Kratos's selfservice.flows.verification.enabled. | `bool` | `true` | no |
| <a name="input_tls_cert_secret_name"></a> [tls\_cert\_secret\_name](#input\_tls\_cert\_secret\_name) | Name of a Kubernetes TLS secret (containing tls.crt and tls.key) to mount into the pod and serve HTTPS from. Typically created by cert-manager. When set, the selfservice UI serves HTTPS directly. | `string` | `null` | no |
| <a name="input_token_hook_api_key"></a> [token\_hook\_api\_key](#input\_token\_hook\_api\_key) | Shared secret Hydra sends in the X-Token-Hook-Api-Key header when calling the token hook. Must be at least 32 characters. If not set and token\_hook\_enabled is true, a random 48-character key is generated; read it back from the token\_hook\_api\_key output to configure Hydra. | `string` | `null` | no |
| <a name="input_token_hook_enabled"></a> [token\_hook\_enabled](#input\_token\_hook\_enabled) | Serve POST /hooks/token, Hydra's token hook. Hydra calls it on every token issuance so claims can be refreshed from Kratos on refresh-token grants, not just at consent time. Hydra must be pointed at the hook separately (see the ory-hydra module's token\_hook variable, or ory-stack's selfservice\_ui\_token\_hook\_enabled). | `bool` | `false` | no |
| <a name="input_tolerations"></a> [tolerations](#input\_tolerations) | Tolerations for selfservice UI pods. | <pre>list(object({<br/>    key      = string<br/>    value    = optional(string)<br/>    operator = optional(string, "Equal")<br/>    effect   = string<br/>  }))</pre> | `[]` | no |
| <a name="input_trust_mounted_ca_cert"></a> [trust\_mounted\_ca\_cert](#input\_trust\_mounted\_ca\_cert) | When true and tls\_cert\_secret\_name is set, point NODE\_EXTRA\_CA\_CERTS at the ca.crt key of the mounted TLS secret so the UI's outbound HTTPS calls (to Kratos/Hydra) trust the issuing CA. Only useful when those upstreams are served by the same in-cluster CA (e.g., cert-manager's self-signed ClusterIssuer). Leave false when the upstream certs are signed by a public CA (Let's Encrypt, corporate trust bundle) that Node.js already trusts, since the mounted secret may not even contain a ca.crt key. | `bool` | `false` | no |
| <a name="input_trusted_client_ids"></a> [trusted\_client\_ids](#input\_trusted\_client\_ids) | List of OAuth2 client IDs that are trusted and can skip the consent screen. | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace where the selfservice UI is deployed. |
| <a name="output_port"></a> [port](#output\_port) | Port the selfservice UI listens on. |
| <a name="output_service_name"></a> [service\_name](#output\_service\_name) | Name of the Kubernetes Service for the selfservice UI. |
| <a name="output_service_url"></a> [service\_url](#output\_service\_url) | Internal URL of the selfservice UI service. Uses https when TLS is enabled. |
| <a name="output_token_hook_api_key"></a> [token\_hook\_api\_key](#output\_token\_hook\_api\_key) | Shared secret Hydra must send when calling the token hook. Null when token\_hook\_enabled is false. |
| <a name="output_token_hook_api_key_header"></a> [token\_hook\_api\_key\_header](#output\_token\_hook\_api\_key\_header) | HTTP header the token hook expects the API key in. |
| <a name="output_token_hook_url"></a> [token\_hook\_url](#output\_token\_hook\_url) | Internal URL of the Hydra token hook served by the selfservice UI. Null when token\_hook\_enabled is false. |
