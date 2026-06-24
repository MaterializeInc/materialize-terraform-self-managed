## Chart values escape hatch

The `helm_values` input deep-merges into the upstream Ory Polis Helm chart's
default values. Use it to override any chart-level setting this module does
not surface as a typed input (for example, `job.nodeSelector` to pin the
migration job to a specific node pool, or `polis.hosted = true` to enable
the multi-tenant admin UI).

The Polis OEL chart is private. To inspect the full set of available keys,
pull and run `helm show values` against the chart. The chart is served via
the Materialize OEL registry proxy with the license-key JWT (the same
credential used for image pulls):

```bash
echo "$MATERIALIZE_LICENSE_KEY_JWT" | helm registry login \
  ory.registry.cloud.materialize.com --username jwt --password-stdin
helm show values oci://ory.registry.cloud.materialize.com/ory-artifacts/helm-oel-polis/polis-oel \
  --version 0.0.20
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.8 |
| <a name="requirement_deepmerge"></a> [deepmerge](#requirement\_deepmerge) | ~> 1.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 2.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 2.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.0.0 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | ~> 4.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_helm"></a> [helm](#provider\_helm) | ~> 2.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | ~> 2.0 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.0.0 |
| <a name="provider_tls"></a> [tls](#provider\_tls) | ~> 4.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [helm_release.polis](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_namespace.polis](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace) | resource |
| [kubernetes_secret.polis](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret) | resource |
| [random_password.admin_api_keys](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.db_encryption_key](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.nextauth_secret](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [tls_private_key.openid_rsa](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_admin_api_keys"></a> [admin\_api\_keys](#input\_admin\_api\_keys) | Bearer token for authenticating requests to Polis admin APIs (set as the API\_KEYS env var inside the Polis container). If null, a random 32-character key is generated. | `string` | `null` | no |
| <a name="input_chart_registry"></a> [chart\_registry](#input\_chart\_registry) | OCI registry hostname for the Polis Helm chart. | `string` | `"europe-docker.pkg.dev"` | no |
| <a name="input_chart_repository"></a> [chart\_repository](#input\_chart\_repository) | OCI repository path for the Polis Helm chart (relative to chart\_registry). | `string` | `"ory-artifacts/helm-oel-polis/polis-oel"` | no |
| <a name="input_chart_version"></a> [chart\_version](#input\_chart\_version) | Polis Helm chart version. See the Ory Polis release notes for the version that pairs with your OEL image tag. | `string` | `"0.0.20"` | no |
| <a name="input_create_namespace"></a> [create\_namespace](#input\_create\_namespace) | Whether to create the Kubernetes namespace. Set to false if the namespace already exists. | `bool` | `true` | no |
| <a name="input_db_encryption_key"></a> [db\_encryption\_key](#input\_db\_encryption\_key) | Symmetric key used by Polis to encrypt sensitive fields (e.g. IdP credentials) before storing them in the database. Required by the chart. If null, a random 32-character key is generated. WARNING: rotating this key invalidates all existing encrypted records, so persist it across applies (e.g., via Terraform state or a Vault lookup). | `string` | `null` | no |
| <a name="input_db_ssl"></a> [db\_ssl](#input\_db\_ssl) | Whether Polis should connect to its database over TLS. Maps to the chart's dbSSL value and the DB\_SSL env var. | `bool` | `true` | no |
| <a name="input_dsn"></a> [dsn](#input\_dsn) | PostgreSQL DSN for Polis. Injected as the DB\_URL env var via a Kubernetes Secret (the chart's built-in secret hardcodes a CockroachDB DSN, so this module always ships its own). Example: postgres://user:password@host:5432/polis?sslmode=require | `string` | n/a | yes |
| <a name="input_external_url"></a> [external\_url](#input\_external\_url) | Externally-reachable HTTPS URL for Polis. Used as the NEXTAUTH\_URL so OIDC and SAML flows redirect through it. Polis does not terminate TLS itself, so HTTPS must be provided by an ingress or LoadBalancer in front of the pod. Example: https://polis.internal.example.com | `string` | n/a | yes |
| <a name="input_extra_env"></a> [extra\_env](#input\_extra\_env) | Additional environment variables for the Polis container as a map of name to value. Wired through the chart's deployment.extraEnvs list. | `map(string)` | `{}` | no |
| <a name="input_helm_values"></a> [helm\_values](#input\_helm\_values) | Additional values to merge into the Helm release. Deep-merged on top of this module's defaults so individual keys can be overridden without rewriting whole blocks. | `any` | `{}` | no |
| <a name="input_hosted"></a> [hosted](#input\_hosted) | When true, Polis runs in 'hosted' mode and exposes the multi-tenant admin UI. Leave false for an embedded single-tenant deployment fronting a single Materialize console. | `bool` | `false` | no |
| <a name="input_idp_enabled"></a> [idp\_enabled](#input\_idp\_enabled) | Enable Polis's IdP routes (SAML/OAuth ACS, /.well-known/, etc.). Required when Polis is acting as an IdP for downstream consumers like Kratos. | `bool` | `true` | no |
| <a name="input_image_pull_policy"></a> [image\_pull\_policy](#input\_image\_pull\_policy) | Image pull policy for Polis pods. | `string` | `"IfNotPresent"` | no |
| <a name="input_image_pull_secrets"></a> [image\_pull\_secrets](#input\_image\_pull\_secrets) | List of Kubernetes secret names (in the Polis namespace) used to pull the OEL image. | `list(string)` | `[]` | no |
| <a name="input_image_registry"></a> [image\_registry](#input\_image\_registry) | Override for the Polis container image registry. Null uses the chart's default (europe-docker.pkg.dev for OEL). | `string` | `null` | no |
| <a name="input_image_repository"></a> [image\_repository](#input\_image\_repository) | Override for the Polis container image repository. Null uses the chart's default (ory-artifacts/ory-enterprise-polis/polis-oel). | `string` | `null` | no |
| <a name="input_image_tag"></a> [image\_tag](#input\_image\_tag) | Override for the Polis container image tag. Null uses the chart's default (typically pinned to the chart's AppVersion). | `string` | `null` | no |
| <a name="input_install_timeout"></a> [install\_timeout](#input\_install\_timeout) | Helm install/upgrade timeout in seconds. | `number` | `600` | no |
| <a name="input_monitoring_enabled"></a> [monitoring\_enabled](#input\_monitoring\_enabled) | When false, the chart's default OTLP endpoints (which point at a kube-prometheus-stack installation in 'observability') are blanked out so Polis doesn't keep trying to reach a non-existent collector. Set to true and override via helm\_values when you have one. | `bool` | `false` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Kubernetes namespace for Ory Polis. | `string` | `"ory-polis"` | no |
| <a name="input_nextauth_acl"></a> [nextauth\_acl](#input\_nextauth\_acl) | Optional NextAuth ACL string. Restricts which email addresses can authenticate to the Polis admin UI. Empty allows all. | `string` | `""` | no |
| <a name="input_nextauth_secret"></a> [nextauth\_secret](#input\_nextauth\_secret) | Secret used by NextAuth.js for session signing. If null, a random 32-character secret is generated. | `string` | `null` | no |
| <a name="input_node_selector"></a> [node\_selector](#input\_node\_selector) | Node selector for Polis pods. | `map(string)` | `{}` | no |
| <a name="input_oci_registry_password"></a> [oci\_registry\_password](#input\_oci\_registry\_password) | Password / token for authenticating to the Polis Helm OCI registry. For GCP Artifact Registry, pass the full contents of a service-account JSON key via file('path/to/key.json'). When null, no authentication is configured (only viable for an anonymous registry). | `string` | `null` | no |
| <a name="input_oci_registry_username"></a> [oci\_registry\_username](#input\_oci\_registry\_username) | Username for authenticating to the Polis Helm OCI registry. For GCP Artifact Registry (the default chart\_registry), use '\_json\_key'. Ignored when oci\_registry\_password is null. | `string` | `"_json_key"` | no |
| <a name="input_port"></a> [port](#input\_port) | Cluster-IP service port for Polis. The container always listens on 5225; this is just the front-side port the service publishes. | `number` | `5225` | no |
| <a name="input_release_name"></a> [release\_name](#input\_release\_name) | Helm release name. Also used as the resource name prefix inside the chart. Defaulting to 'polis' produces simple resource names like 'polis' / 'polis-migration' because the chart's fullname helper collapses '<release>-<chart>' when one contains the other. | `string` | `"polis"` | no |
| <a name="input_replica_count"></a> [replica\_count](#input\_replica\_count) | Number of Polis replicas. | `number` | `2` | no |
| <a name="input_resources"></a> [resources](#input\_resources) | Resource requests and limits for Polis pods. | <pre>object({<br/>    requests = optional(object({<br/>      cpu    = optional(string, "250m")<br/>      memory = optional(string, "512Mi")<br/>    }))<br/>    limits = optional(object({<br/>      cpu    = optional(string)<br/>      memory = optional(string, "512Mi")<br/>    }))<br/>  })</pre> | <pre>{<br/>  "limits": {},<br/>  "requests": {}<br/>}</pre> | no |
| <a name="input_saml_audience"></a> [saml\_audience](#input\_saml\_audience) | Optional SAML audience identifier (Polis's SAML entity ID). When set, injected as the SAML\_AUDIENCE env var on the Polis container. Must match the audience configured on the upstream IdP. Leave null to inherit Polis's built-in default. | `string` | `null` | no |
| <a name="input_tolerations"></a> [tolerations](#input\_tolerations) | Tolerations for Polis pods. | <pre>list(object({<br/>    key      = string<br/>    value    = optional(string)<br/>    operator = optional(string, "Equal")<br/>    effect   = string<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_admin_api_keys"></a> [admin\_api\_keys](#output\_admin\_api\_keys) | API key for Polis admin APIs. |
| <a name="output_db_encryption_key"></a> [db\_encryption\_key](#output\_db\_encryption\_key) | Symmetric key used to encrypt sensitive fields at rest in the Polis database. Persist across applies; rotating invalidates existing encrypted records. |
| <a name="output_external_url"></a> [external\_url](#output\_external\_url) | Externally-reachable HTTPS URL for Polis, as supplied via var.external\_url. This is the browser-facing URL that SAML/OAuth flows redirect through, and the issuer URL that upstream OIDC consumers (e.g., Kratos social sign-in) should point at. |
| <a name="output_internal_url"></a> [internal\_url](#output\_internal\_url) | Internal cluster URL for Polis (SSO, SCIM, OAuth endpoints). Always http because Polis itself does not terminate TLS, it runs as a NextJS app that only speaks plain HTTP on its configured port. Callers of this module are responsible for putting a TLS-terminating proxy in front, typically a cloud LoadBalancer service using cert-manager certs, a cloud-native cert like AWS ACM or GCP managed certs, or an ingress controller like nginx. |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace where Ory Polis is deployed. |
| <a name="output_nextauth_secret"></a> [nextauth\_secret](#output\_nextauth\_secret) | NextAuth.js session signing secret. |
| <a name="output_release_name"></a> [release\_name](#output\_release\_name) | Helm release name. |
| <a name="output_service_name"></a> [service\_name](#output\_service\_name) | Kubernetes service name for Polis. Set from var.release\_name via fullnameOverride so it stays predictable. |
