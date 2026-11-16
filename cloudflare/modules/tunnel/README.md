# Cloudflare Tunnel ingress

Exposes a Materialize environment's console and pgwire through a Cloudflare
Tunnel, with Cloudflare Access in front of both. The environment keeps
internal load balancers only; `cloudflared` connectors running next to it
(for example `gcp/modules/cloudflared-connector`) carry the traffic.

- The console is served over HTTPS at `console_hostname`.
- pgwire, when `sql_hostname` is set, is reached with
  `cloudflared access tcp --hostname <sql_hostname> --url localhost:<port>`.
- Access allows `access_email_domains` and `access_emails` through the
  identity providers in `allowed_idps`, plus the email one-time PIN with
  `enable_one_time_pin`. Machine clients use a service token
  (`create_service_token`).

The hostnames must be in a zone in the same Cloudflare account as the
tunnel: Cloudflare only routes `cfargotunnel.com` CNAMEs within one account.
The zone's edge certificate must also cover them; on Universal SSL that
means one label under the apex.

## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_cloudflare"></a> [cloudflare](#requirement\_cloudflare) | ~> 5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_cloudflare"></a> [cloudflare](#provider\_cloudflare) | ~> 5.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [cloudflare_dns_record.this](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/dns_record) | resource |
| [cloudflare_zero_trust_access_application.this](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/zero_trust_access_application) | resource |
| [cloudflare_zero_trust_access_identity_provider.otp](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/zero_trust_access_identity_provider) | resource |
| [cloudflare_zero_trust_access_policy.service_token](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/zero_trust_access_policy) | resource |
| [cloudflare_zero_trust_access_policy.this](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/zero_trust_access_policy) | resource |
| [cloudflare_zero_trust_access_service_token.this](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/zero_trust_access_service_token) | resource |
| [cloudflare_zero_trust_tunnel_cloudflared.this](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/zero_trust_tunnel_cloudflared) | resource |
| [cloudflare_zero_trust_tunnel_cloudflared_config.this](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/zero_trust_tunnel_cloudflared_config) | resource |
| [cloudflare_zero_trust_tunnel_cloudflared_token.this](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/data-sources/zero_trust_tunnel_cloudflared_token) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_access_email_domains"></a> [access\_email\_domains](#input\_access\_email\_domains) | Email domains allowed through Cloudflare Access. | `list(string)` | `[]` | no |
| <a name="input_access_emails"></a> [access\_emails](#input\_access\_emails) | Individual email addresses allowed through Cloudflare Access. | `list(string)` | `[]` | no |
| <a name="input_account_id"></a> [account\_id](#input\_account\_id) | Cloudflare account ID that owns the tunnel and the Access applications. | `string` | n/a | yes |
| <a name="input_allowed_idps"></a> [allowed\_idps](#input\_allowed\_idps) | IDs of the Access identity providers offered on the login page. Name them explicitly: with an empty list, a login method added to the account later (for example one-time PIN) was not offered. | `list(string)` | `[]` | no |
| <a name="input_console_hostname"></a> [console\_hostname](#input\_console\_hostname) | Public hostname for the Materialize console. Must be covered by the zone's edge certificate; on a Universal SSL zone that means a single label under the apex (for example `mz-console.example.com`). | `string` | n/a | yes |
| <a name="input_console_origin"></a> [console\_origin](#input\_console\_origin) | Origin URL cloudflared forwards console traffic to, for example `https://10.0.0.5:8080`. | `string` | n/a | yes |
| <a name="input_create_service_token"></a> [create\_service\_token](#input\_create\_service\_token) | Create an Access service token allowed through both applications, for machine clients (dbt, BI tools, CI) that cannot complete an interactive IdP login. | `bool` | `false` | no |
| <a name="input_enable_one_time_pin"></a> [enable\_one\_time\_pin](#input\_enable\_one\_time\_pin) | Create Cloudflare's email one-time PIN login method and offer it on both applications, alongside `allowed_idps`. Useful when no IdP is configured, or the configured one is broken. Cloudflare allows one per account: if the account already has one, leave this false and pass its ID in `allowed_idps`. It is account-wide, so destroying this module removes it for every application. | `bool` | `false` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the tunnel. Also used to name the Access applications and policy. | `string` | n/a | yes |
| <a name="input_origin_no_tls_verify"></a> [origin\_no\_tls\_verify](#input\_origin\_no\_tls\_verify) | Skip verifying the origin's TLS certificate. Needed while the console serves a self-signed certificate. | `bool` | `false` | no |
| <a name="input_service_token_duration"></a> [service\_token\_duration](#input\_service\_token\_duration) | Lifetime of the service token, for example `8760h`. | `string` | `"8760h"` | no |
| <a name="input_session_duration"></a> [session\_duration](#input\_session\_duration) | How long an Access session lasts before users must log in again. | `string` | `"24h"` | no |
| <a name="input_sql_hostname"></a> [sql\_hostname](#input\_sql\_hostname) | Public hostname for pgwire. Clients reach it with `cloudflared access tcp`. Set to null to expose only the console. | `string` | `null` | no |
| <a name="input_sql_origin"></a> [sql\_origin](#input\_sql\_origin) | Origin cloudflared forwards pgwire traffic to, for example `tcp://10.0.0.6:6875`. Required when `sql_hostname` is set. | `string` | `null` | no |
| <a name="input_zone_id"></a> [zone\_id](#input\_zone\_id) | ID of the Cloudflare zone the hostnames are created in. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_console_url"></a> [console\_url](#output\_console\_url) | URL of the Materialize console. |
| <a name="output_service_token"></a> [service\_token](#output\_service\_token) | Access service token for machine clients, sent as the `CF-Access-Client-Id` and `CF-Access-Client-Secret` headers, or with `cloudflared access tcp --service-token-id/--service-token-secret`. Null unless `create_service_token` is set. |
| <a name="output_sql_hostname"></a> [sql\_hostname](#output\_sql\_hostname) | Hostname to pass to `cloudflared access tcp --hostname` for pgwire, or null. |
| <a name="output_tunnel_id"></a> [tunnel\_id](#output\_tunnel\_id) | ID of the Cloudflare tunnel. |
| <a name="output_tunnel_token"></a> [tunnel\_token](#output\_tunnel\_token) | Token cloudflared connectors use to run the tunnel. |
