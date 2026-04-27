## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0.0 |
| <a name="requirement_kubectl"></a> [kubectl](#requirement\_kubectl) | ~> 2.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.10.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_kubectl"></a> [kubectl](#provider\_kubectl) | 2.2.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | 3.1.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [kubectl_manifest.cluster_issuer](https://registry.terraform.io/providers/alekc/kubectl/latest/docs/resources/manifest) | resource |
| [kubernetes_secret_v1.cloudflare_api_token](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret_v1) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_acme_environment"></a> [acme\_environment](#input\_acme\_environment) | Let's Encrypt environment. Use 'staging' while iterating to avoid the production rate limits (50 certs/week per registered domain). Staging certs are signed by an untrusted CA so browsers will warn. Switch to 'production' once the integration is stable. | `string` | `"staging"` | no |
| <a name="input_cloudflare_api_token"></a> [cloudflare\_api\_token](#input\_cloudflare\_api\_token) | Cloudflare API token with Zone:Read and DNS:Edit permission, scoped to the zone(s) listed in dns\_zones. Required when dns\_provider is 'cloudflare'. Create one at https://dash.cloudflare.com/profile/api-tokens. | `string` | `null` | no |
| <a name="input_dns_provider"></a> [dns\_provider](#input\_dns\_provider) | DNS provider used to satisfy ACME dns-01 challenges. Only 'cloudflare' is supported today; other providers can be added by extending this module. | `string` | `"cloudflare"` | no |
| <a name="input_dns_zones"></a> [dns\_zones](#input\_dns\_zones) | DNS zones (apex domains) the issuer is allowed to solve challenges for. Used as the dnsZones selector on the solver so the ClusterIssuer only attempts challenges for hostnames inside these zones. Example: ["bobby.sh"]. | `list(string)` | n/a | yes |
| <a name="input_email"></a> [email](#input\_email) | Contact email used for Let's Encrypt account registration. Let's Encrypt sends expiry warnings and account notifications here. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name of the ClusterIssuer to create. Used as a prefix for the ACME account key Secret and the DNS provider credential Secret. | `string` | `"letsencrypt"` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace where DNS provider credential Secrets are created. Should be the cert-manager namespace so that cert-manager can read the Secrets when solving challenges. | `string` | `"cert-manager"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_issuer_kind"></a> [issuer\_kind](#output\_issuer\_kind) | Kind of the issuer (always ClusterIssuer). |
| <a name="output_issuer_name"></a> [issuer\_name](#output\_issuer\_name) | Name of the ClusterIssuer that was created. |
| <a name="output_issuer_ref"></a> [issuer\_ref](#output\_issuer\_ref) | Reference object suitable for passing to modules that accept a cert-manager issuer reference. |
