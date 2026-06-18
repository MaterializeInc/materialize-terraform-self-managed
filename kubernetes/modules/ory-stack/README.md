## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.8 |
| <a name="requirement_deepmerge"></a> [deepmerge](#requirement\_deepmerge) | ~> 1.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 2.0 |
| <a name="requirement_kubectl"></a> [kubectl](#requirement\_kubectl) | 2.4.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 2.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_kubectl"></a> [kubectl](#provider\_kubectl) | 2.4.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | ~> 2.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_ory_hydra"></a> [ory\_hydra](#module\_ory\_hydra) | ../ory-hydra | n/a |
| <a name="module_ory_kratos"></a> [ory\_kratos](#module\_ory\_kratos) | ../ory-kratos | n/a |
| <a name="module_ory_polis"></a> [ory\_polis](#module\_ory\_polis) | ../ory-polis | n/a |
| <a name="module_ory_selfservice_ui"></a> [ory\_selfservice\_ui](#module\_ory\_selfservice\_ui) | ../ory-selfservice-ui | n/a |

## Resources

| Name | Type |
|------|------|
| [kubectl_manifest.materialize_oauth2_client](https://registry.terraform.io/providers/alekc/kubectl/2.4.0/docs/resources/manifest) | resource |
| [kubectl_manifest.ory_certificate](https://registry.terraform.io/providers/alekc/kubectl/2.4.0/docs/resources/manifest) | resource |
| [kubernetes_config_map_v1.polis_tls_proxy](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/config_map_v1) | resource |
| [kubernetes_deployment_v1.polis_tls_proxy](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/deployment_v1) | resource |
| [kubernetes_namespace.ory](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace) | resource |
| [kubernetes_network_policy_v1.materialize_to_ory_egress](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/network_policy_v1) | resource |
| [kubernetes_network_policy_v1.ory_from_materialize_ingress](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/network_policy_v1) | resource |
| [kubernetes_secret.ory_oel_registry](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret) | resource |
| [kubernetes_service_v1.console_https_lb](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service_v1) | resource |
| [kubernetes_service_v1.ory_lb](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service_v1) | resource |
| [kubernetes_secret_v1.oauth2_client](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/data-sources/secret_v1) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cert_issuer_ref"></a> [cert\_issuer\_ref](#input\_cert\_issuer\_ref) | cert-manager issuer reference used for the browser-facing TLS certificates. Object with 'name' and 'kind' (e.g. {name = '...', kind = 'ClusterIssuer'}). | <pre>object({<br/>    name = string<br/>    kind = string<br/>  })</pre> | n/a | yes |
| <a name="input_cert_issuer_signs_cluster_local"></a> [cert\_issuer\_signs\_cluster\_local](#input\_cert\_issuer\_signs\_cluster\_local) | Set to true when the issuer can sign single-label cluster.local SANs (typically the built-in self-signed ClusterIssuer). When true the cert SANs include the in-cluster service hostnames so in-cluster callers can hit the services directly; when false the SAN is dropped and in-cluster callers route via the external hostname (hairpin NAT through the LB). | `bool` | n/a | yes |
| <a name="input_cookie_parent_domain"></a> [cookie\_parent\_domain](#input\_cookie\_parent\_domain) | Parent domain used as the cookie domain for Kratos session and CSRF cookies so they apply across sibling subdomains. Defaults to the parent domain of kratos\_fqdn (e.g. kratos.example.com -> example.com). Falls back to kratos\_fqdn itself when it has no '.' separator. | `string` | `null` | no |
| <a name="input_create_namespace"></a> [create\_namespace](#input\_create\_namespace) | Whether the module should create the Ory namespace. Set to false if it already exists. | `bool` | `true` | no |
| <a name="input_enable_polis"></a> [enable\_polis](#input\_enable\_polis) | Deploy Ory Polis (SAML-to-OIDC bridge) as part of the stack. When true, polis\_fqdn and polis\_dsn must be provided. | `bool` | `false` | no |
| <a name="input_hydra_dsn"></a> [hydra\_dsn](#input\_hydra\_dsn) | Postgres DSN for Hydra. Cloud-specific, computed by the caller from the database module outputs. | `string` | n/a | yes |
| <a name="input_hydra_fqdn"></a> [hydra\_fqdn](#input\_hydra\_fqdn) | Fully-qualified domain name for the Hydra OAuth2 public API (e.g. hydra.example.com). Used as the OIDC issuer URL. | `string` | n/a | yes |
| <a name="input_hydra_helm_values"></a> [hydra\_helm\_values](#input\_hydra\_helm\_values) | Additional helm\_values merged on top of the Hydra defaults. Use sparingly; the module already wires the values that the enterprise setup requires. | `any` | `{}` | no |
| <a name="input_kratos_dsn"></a> [kratos\_dsn](#input\_kratos\_dsn) | Postgres DSN for Kratos. Cloud-specific, computed by the caller from the database module outputs. | `string` | n/a | yes |
| <a name="input_kratos_fqdn"></a> [kratos\_fqdn](#input\_kratos\_fqdn) | Fully-qualified domain name for the Kratos public API (e.g. kratos.example.com). Used by the selfservice UI and as a browser redirect target. | `string` | n/a | yes |
| <a name="input_kratos_helm_values"></a> [kratos\_helm\_values](#input\_kratos\_helm\_values) | Additional helm\_values merged on top of the Kratos defaults. Use sparingly; the module already wires the values that the enterprise setup requires. | `any` | `{}` | no |
| <a name="input_lb_annotations"></a> [lb\_annotations](#input\_lb\_annotations) | Annotations applied to the public LoadBalancer Services (Hydra, Kratos, UI, and the Materialize console). Use this to set cloud-specific LB knobs (Azure internal flag, GKE LB type, AWS LBC settings). | `map(string)` | `{}` | no |
| <a name="input_lb_external_traffic_policy"></a> [lb\_external\_traffic\_policy](#input\_lb\_external\_traffic\_policy) | Value for spec.externalTrafficPolicy on the LoadBalancer Services. Leave null to inherit the cluster default; set to 'Local' on AWS to preserve client source IPs through the NLB. | `string` | `null` | no |
| <a name="input_lb_load_balancer_class"></a> [lb\_load\_balancer\_class](#input\_lb\_load\_balancer\_class) | Value for spec.loadBalancerClass on the LoadBalancer Services. Leave null on Azure and GCP; set to 'service.k8s.aws/nlb' on AWS to route through the AWS Load Balancer Controller. | `string` | `null` | no |
| <a name="input_lb_source_cidrs"></a> [lb\_source\_cidrs](#input\_lb\_source\_cidrs) | CIDR blocks allowed to reach the Ory public ports (Hydra 4444, Kratos 4433, selfservice UI 3000) via the NetworkPolicy. Defaults to all sources; tighten to your LB or office CIDR ranges to restrict ingress. | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_license_key_jwt"></a> [license\_key\_jwt](#input\_license\_key\_jwt) | Materialize license key JWT. Used as the password in the imagePullSecret to authenticate to the Ory registry proxy. The proxy validates the JWT signature, checks the ory entitlement, and forwards to Ory's Artifact Registry using Materialize's service account. Same JWT used by the materialize-instance module's license\_key. | `string` | n/a | yes |
| <a name="input_materialize_console_fqdn"></a> [materialize\_console\_fqdn](#input\_materialize\_console\_fqdn) | Fully-qualified domain name the Materialize console will be served on (e.g. console.example.com). Required when materialize\_namespace is set; used for the OAuth2 redirect URI and Hydra CORS. | `string` | `null` | no |
| <a name="input_materialize_instance_name"></a> [materialize\_instance\_name](#input\_materialize\_instance\_name) | Name of the Materialize instance. Required when materialize\_namespace is set; used for the console HTTPS Service selector and name prefix. | `string` | `null` | no |
| <a name="input_materialize_instance_resource_id"></a> [materialize\_instance\_resource\_id](#input\_materialize\_instance\_resource\_id) | resource\_id from the Materialize instance status. Required when materialize\_namespace is set; used for the console HTTPS Service selector. | `string` | `null` | no |
| <a name="input_materialize_namespace"></a> [materialize\_namespace](#input\_materialize\_namespace) | Namespace of the Materialize instance to wire up. When set, the module creates an OAuth2Client CRD in Hydra, NetworkPolicies bridging the two namespaces, and the console HTTPS LoadBalancer. Set to null to deploy Ory without Materialize integration. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Kubernetes namespace for the Ory components (Kratos, Hydra, selfservice UI). | `string` | `"ory"` | no |
| <a name="input_node_selector"></a> [node\_selector](#input\_node\_selector) | Node selector applied to all Ory pods (Kratos, Hydra, selfservice UI). | `map(string)` | `{}` | no |
| <a name="input_oauth2_client_audience"></a> [oauth2\_client\_audience](#input\_oauth2\_client\_audience) | Audience value(s) the OAuth2 client embeds in issued JWTs. Materialize validates this against its OIDC\_AUDIENCE setting. | `list(string)` | <pre>[<br/>  "materialize"<br/>]</pre> | no |
| <a name="input_oauth2_client_name"></a> [oauth2\_client\_name](#input\_oauth2\_client\_name) | Name of the Hydra OAuth2Client CRD registered for Materialize. Also the Secret name where Hydra Maester writes the credentials. | `string` | `"materialize-oauth2-client"` | no |
| <a name="input_oauth2_client_scope"></a> [oauth2\_client\_scope](#input\_oauth2\_client\_scope) | OAuth2 scopes requested by the Materialize console during the authorization code flow. | `string` | `"openid profile email offline"` | no |
| <a name="input_oel_image_tag"></a> [oel\_image\_tag](#input\_oel\_image\_tag) | Tag for the OEL Kratos and Hydra images. | `string` | n/a | yes |
| <a name="input_oel_registry"></a> [oel\_registry](#input\_oel\_registry) | Base registry URL for Ory Enterprise License (OEL) images. Defaults to the production Materialize-hosted registry proxy (ory.registry.cloud.materialize.com/ory-artifacts). Override for staging (ory.registry.staging.cloud.materialize.com/ory-artifacts) or a dev stack. The Kratos and Hydra image repos are derived from this prefix. | `string` | `"ory.registry.cloud.materialize.com/ory-artifacts"` | no |
| <a name="input_oel_registry_secret_name"></a> [oel\_registry\_secret\_name](#input\_oel\_registry\_secret\_name) | Name of the imagePullSecrets Secret created in the Ory namespace. | `string` | `"ory-oel-registry"` | no |
| <a name="input_polis_admin_api_keys"></a> [polis\_admin\_api\_keys](#input\_polis\_admin\_api\_keys) | Bearer token for Polis admin APIs. When null, the module generates a random 32-character key. Persist across applies, rotating invalidates admin-tool access. | `string` | `null` | no |
| <a name="input_polis_chart_oci_password"></a> [polis\_chart\_oci\_password](#input\_polis\_chart\_oci\_password) | Password for authenticating to the Polis chart OCI registry. Null falls back to license\_key\_jwt (proxy path). Set to the contents of a GCP service-account JSON key when pulling the chart directly from GCP Artifact Registry. | `string` | `null` | no |
| <a name="input_polis_chart_oci_username"></a> [polis\_chart\_oci\_username](#input\_polis\_chart\_oci\_username) | Username for authenticating to the Polis chart OCI registry. Defaults to 'jwt' (proxy path); use '\_json\_key' when pulling directly from GCP Artifact Registry. | `string` | `"jwt"` | no |
| <a name="input_polis_chart_registry"></a> [polis\_chart\_registry](#input\_polis\_chart\_registry) | OCI registry host the Polis Helm chart is pulled from. Null falls back to the OEL registry proxy host (derived from oel\_registry), which is the default and recommended path. Override if you want to bypass the proxy and pull the chart directly from a different OCI registry. | `string` | `null` | no |
| <a name="input_polis_chart_repository"></a> [polis\_chart\_repository](#input\_polis\_chart\_repository) | OCI repository path for the Polis Helm chart (no leading slash, no registry host). Null falls back to the proxy-aware path derived from oel\_registry. Override when the chart lives outside the proxy path, e.g. 'ory-artifacts/helm-oel-polis/polis-oel' on GCP Artifact Registry. | `string` | `null` | no |
| <a name="input_polis_chart_version"></a> [polis\_chart\_version](#input\_polis\_chart\_version) | Polis Helm chart version pulled from the OEL registry. | `string` | `"0.0.20"` | no |
| <a name="input_polis_db_encryption_key"></a> [polis\_db\_encryption\_key](#input\_polis\_db\_encryption\_key) | Symmetric key used by Polis to encrypt sensitive fields at rest in its database. When null, a random 32-character key is generated. WARNING: rotating invalidates existing encrypted records. | `string` | `null` | no |
| <a name="input_polis_dsn"></a> [polis\_dsn](#input\_polis\_dsn) | Postgres DSN for Polis. Cloud-specific, computed by the caller from the database module outputs. Required when enable\_polis is true. | `string` | `null` | no |
| <a name="input_polis_fqdn"></a> [polis\_fqdn](#input\_polis\_fqdn) | Fully-qualified domain name for Polis (e.g. polis.example.com). Used as the NEXTAUTH\_URL and the cert SAN; SAML and OAuth callbacks redirect through it. Required when enable\_polis is true. | `string` | `null` | no |
| <a name="input_polis_helm_values"></a> [polis\_helm\_values](#input\_polis\_helm\_values) | Additional helm\_values merged on top of the Polis defaults. | `any` | `{}` | no |
| <a name="input_polis_nextauth_secret"></a> [polis\_nextauth\_secret](#input\_polis\_nextauth\_secret) | Secret used by NextAuth.js for session signing in Polis. When null, a random 32-character secret is generated. | `string` | `null` | no |
| <a name="input_polis_oel_image_tag"></a> [polis\_oel\_image\_tag](#input\_polis\_oel\_image\_tag) | Tag for the Polis OEL image. Polis releases independently of Kratos/Hydra, so it has its own tag knob. When null, the chart's pinned AppVersion is used. | `string` | `null` | no |
| <a name="input_selfservice_ui_extra_env"></a> [selfservice\_ui\_extra\_env](#input\_selfservice\_ui\_extra\_env) | Additional environment variables passed to the selfservice UI container. | `map(string)` | `{}` | no |
| <a name="input_ui_fqdn"></a> [ui\_fqdn](#input\_ui\_fqdn) | Fully-qualified domain name for the Ory selfservice UI (e.g. id.example.com). | `string` | n/a | yes |
| <a name="input_upstream_oidc_providers"></a> [upstream\_oidc\_providers](#input\_upstream\_oidc\_providers) | Optional upstream OIDC providers (Okta, Entra, Auth0, Google, etc.) exposed as social sign-in buttons on the selfservice UI. Each entry's redirect URI is registered at the upstream IdP as https://<kratos\_fqdn>/self-service/methods/oidc/callback/<id>. | <pre>list(object({<br/>    id            = string<br/>    provider      = optional(string, "generic")<br/>    client_id     = string<br/>    client_secret = string<br/>    issuer_url    = string<br/>    scope         = optional(list(string), ["openid", "email", "profile"])<br/>    label         = optional(string)<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_console_https_service_name"></a> [console\_https\_service\_name](#output\_console\_https\_service\_name) | Name of the Materialize console HTTPS LoadBalancer Service. Null when materialize\_namespace is not set. |
| <a name="output_hydra_external_url"></a> [hydra\_external\_url](#output\_hydra\_external\_url) | External (browser-facing) URL for Hydra. Use this as the OIDC issuer in Materialize. |
| <a name="output_hydra_namespace"></a> [hydra\_namespace](#output\_hydra\_namespace) | Namespace of the Hydra deployment (same as namespace; kept for parity with submodule outputs). |
| <a name="output_kratos_external_url"></a> [kratos\_external\_url](#output\_kratos\_external\_url) | External (browser-facing) URL for Kratos public API. |
| <a name="output_kratos_namespace"></a> [kratos\_namespace](#output\_kratos\_namespace) | Namespace of the Kratos deployment (same as namespace; kept for parity with submodule outputs). |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace where Ory is deployed. |
| <a name="output_oauth2_client_id"></a> [oauth2\_client\_id](#output\_oauth2\_client\_id) | Hydra-Maester-generated OAuth2 client ID for Materialize. Null when materialize\_namespace is not set, or when the secret has not yet been populated by Hydra Maester (which can happen on a refresh that runs before Maester reconciles). |
| <a name="output_oauth2_client_secret_name"></a> [oauth2\_client\_secret\_name](#output\_oauth2\_client\_secret\_name) | Name of the Secret that holds the Hydra-Maester-generated OAuth2 client credentials. Null when materialize\_namespace is not set. |
| <a name="output_oauth2_client_secret_namespace"></a> [oauth2\_client\_secret\_namespace](#output\_oauth2\_client\_secret\_namespace) | Namespace of the OAuth2 client credentials Secret. Null when materialize\_namespace is not set. |
| <a name="output_oel_registry_secret_name"></a> [oel\_registry\_secret\_name](#output\_oel\_registry\_secret\_name) | Name of the dockerconfigjson Secret holding OEL registry credentials, in the Ory namespace. |
| <a name="output_polis_admin_api_keys"></a> [polis\_admin\_api\_keys](#output\_polis\_admin\_api\_keys) | API key for Polis admin APIs (generated or supplied). Null when enable\_polis is false. |
| <a name="output_polis_db_encryption_key"></a> [polis\_db\_encryption\_key](#output\_polis\_db\_encryption\_key) | Symmetric key used by Polis to encrypt sensitive fields at rest. Persist across applies, rotating invalidates existing records. Null when enable\_polis is false. |
| <a name="output_polis_external_url"></a> [polis\_external\_url](#output\_polis\_external\_url) | External (browser-facing) URL for Polis. Null when enable\_polis is false. |
| <a name="output_ui_external_url"></a> [ui\_external\_url](#output\_ui\_external\_url) | External (browser-facing) URL for the Ory selfservice UI. |
| <a name="output_ui_namespace"></a> [ui\_namespace](#output\_ui\_namespace) | Namespace of the selfservice UI deployment (same as namespace; kept for parity with submodule outputs). |
