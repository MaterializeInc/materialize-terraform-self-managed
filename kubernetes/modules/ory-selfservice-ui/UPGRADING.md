# Upgrading the Ory selfservice UI

## Swapping `oryd/kratos-selfservice-ui-node` for `ory-selfservice`

This module now deploys Materialize's own service,
[`ory-selfservice`](https://github.com/MaterializeInc/ory-selfservice), instead of the
upstream `oryd/kratos-selfservice-ui-node` reference UI:

| | before | after |
|---|---|---|
| `image_repository` | `oryd/kratos-selfservice-ui-node` | `materialize/ory-selfservice` |
| `image_tag` | `v25.4.0` | `v0.3.0` |

The image is public on Docker Hub. Air-gapped installs mirror it into their own registry
and point `image_repository` at the mirror.

The new image is a drop-in replacement: same port (3000), same health endpoints
(`/health/alive`, `/health/ready`), same uid (10000), and the same environment variables
(`PORT`, `KRATOS_PUBLIC_URL`, `KRATOS_BROWSER_URL`, `KRATOS_ADMIN_URL`, `HYDRA_ADMIN_URL`,
`COOKIE_SECRET`, `CSRF_COOKIE_SECRET`, `CSRF_COOKIE_NAME`, `TRUSTED_CLIENT_IDS`,
`PROJECT_NAME`, `TLS_CERT_PATH`, `TLS_KEY_PATH`, `NODE_EXTRA_CA_CERTS`,
`DANGEROUSLY_DISABLE_SECURE_CSRF_COOKIES`).

### The `patch-consent` initContainer is gone

The old deployment ran an initContainer that rewrote `/usr/src/app/lib/routes/consent.js`
inside the upstream image, so that identity traits (`groups`) and the email landed on the
access token and the client's configured audience was granted. `ory-selfservice` does that
natively, so the initContainer, its `consent-patched` `emptyDir` volume and the
`consent.js` volume mount are removed. Which traits are copied is now configuration
(`claim_traits_id_token` / `claim_traits_access_token`), not a `sed`-style patch that
breaks whenever upstream reshuffles its source.

Because nothing needs to be written at runtime any more, the pod now runs with
`readOnlyRootFilesystem: true`, all capabilities dropped, `runAsNonRoot` and the
`RuntimeDefault` seccomp profile.

The patch also carried the stopgap default audience for DCR-registered clients
(#467). Its `default_access_token_audience` input is replaced by
`dcr_default_audience` (plus `dcr_audience_allowlist` for RFC 8707 `resource`
requests). On `ory-stack`, `dcr_default_audience` keeps its name and meaning, so
callers of the stack need no change. The image also still reads the old
`MZ_DEFAULT_ACCESS_TOKEN_AUDIENCE` variable as an alias.

### The console no longer shows a consent screen

`ory-stack` now sets `skipConsent = true` on the Materialize console's OAuth2
client. Hydra still calls the consent endpoint for it, and `ory-selfservice`
adds the email and groups claims without showing a page. This only works with
`ory-selfservice`: the old image returned tokens without those claims when
consent was skipped. Self-registered (DCR) clients still see the consent screen.

### Rollout and rollback

This is an in-place rolling update: the Deployment's name, selector labels
(`app.kubernetes.io/name = kratos-selfservice-ui-node`) and Service are unchanged, so
existing deployments roll pod-by-pod like any other image bump. Deployment selectors are
immutable, which is why the historical label value is kept even though the image changed;
`ory-stack`'s selfservice UI LoadBalancer selects on the same labels.

To roll back, revert the module version (or pin `image_repository` /`image_tag` back to
`oryd/kratos-selfservice-ui-node:v25.4.0`) and apply; the old module version restores the
initContainer along with the old image. Sessions are cookie-based and the cookie secrets
are unchanged, so users stay signed in across the roll in both directions.

## Security defaults that come with ory-selfservice v0.3.0

What the image, `ory-kratos` and `ory-stack` enforce together:

Existing deployments have a few steps to take; see the v17.0.0 upgrade notes in the
[root README](../../../README.md#upgrade-notes).

- **`email` and `groups` come from the identity's `metadata_public`, never its traits.**
  During SSO registration Kratos keeps any `traits` the user submits over the IdP mapper's
  values, so a user could otherwise put someone else's email on their token. The claim
  mapper writes the lowercased email and the groups to `metadata_public`, which only the
  mapper and the admin API can write. The UI refuses an identity whose `traits.email`
  differs from `metadata_public.email`, one with no `metadata_public.email`, and an email
  that is not email-shaped.
- **Each IdP has its own claim mapper.** Every entry in `upstream_identity_providers` and
  `saml_providers` needs `allowed_email_domains`; sign-in with any other email domain
  fails (exact match on the lowercased domain, so list subdomains separately).
  `allowed_groups` and `group_prefix` limit which groups an IdP can grant; groups only
  count when the claim is an array, and only its string elements.
- **OIDC emails must be verified.** `require_email_verified` defaults to true for OIDC
  providers (`email_verified` true or `"true"`) and false for SAML, which has no such
  claim. Microsoft Entra ID does not send `email_verified` by default; set it to false
  there and rely on `allowed_email_domains`.
- **Kratos cookies are not widened automatically.** `ory-stack` no longer derives a parent
  domain from the Kratos hostname. Set `kratos_cookie_domain` to the narrowest domain that
  covers Kratos and the UI (it is required whenever they are on different hosts, which
  with the UI on its own `ui_fqdn` is always), ideally one that holds only the Ory
  hostnames: every host under it receives the Kratos session cookie.
- **Sessions last 8 hours** (`kratos_session_lifespan_seconds`), and Hydra remembers a
  sign-in for as long, which bounds how long a user removed at the IdP can authorize new
  clients. It may not exceed `selfservice_ui_token_hook_max_auth_age_seconds`.
- **The identity schema has no password identifier** and only marks the email for
  recovery or verification when those flows are on, so a second IdP cannot collide with
  an existing identity. It also refuses traits it doesn't define
  (`additionalProperties: false`).
- **The token hook is on by default** wherever the selfservice UI is deployed. Hydra
  checks every token issuance with it, so refresh tokens stop working for deactivated
  users, and it only counts active Kratos sessions that signed in through OIDC or SAML.
- **Refresh chains are bounded.** The hook refuses user tokens once the user hasn't
  signed in through the IdP for `selfservice_ui_token_hook_max_auth_age_seconds`
  (default 7 days), so groups the IdP removed don't live on through refresh tokens.
  Revoking a user's Kratos sessions does not end their refresh tokens; deactivate the
  identity or revoke their Hydra consent.
- **SCIM does not deprovision.** Polis's SCIM directory is not synced into Kratos, so
  deactivating a user at the IdP ends their access only when their Kratos session expires
  or the max auth age passes. Delete the Kratos identity to end it sooner.
- **Machine tokens need an operator-managed client.** The hook refuses
  `client_credentials` tokens for clients without `metadata.materialize_managed: true`,
  so a self-registered client can't mint tokens for Materialize without a user.
- **Polis's `CLIENT_SECRET_VERIFIER` is random** instead of `dummy`. To also tie SAML
  assertions to this deployment, set `polis_saml_audience` to the Polis URL and use the
  same value as the IdP app's Audience URI; by default Polis keeps its shared
  `https://saml.boxyhq.com`.
- **Kratos cleans up after itself.** The chart's cleanup CronJob deletes expired
  sessions, flows and continuity rows hourly, keeping them for the token hook's max
  auth age after expiry, since the hook reads the last IdP sign-in from them.
- **Logs hash emails and groups by default** (`selfservice_ui_log_redact_pii`). Set it to
  false temporarily while debugging sign-in issues.
- **Logout works in consent-only mode.** Hydra's logout endpoint is served whether or
  not the screens are on.
- **Hydra restarts when the token hook key changes**, instead of failing every token
  request until its pods happen to restart.
- **The claim inputs are split:** `claim_metadata_public_*` (default `groups`) and
  `claim_traits_*` (default empty). The image refuses `groups`, `email` and standard
  token claims in the trait lists, and the same name in both lists.
- **`remember_consent_for_seconds` must be at least 1**: Hydra treats 0 as remembering
  consent forever.

## Security changes that come with ory-selfservice v0.2.5

- **The console's `OAuth2Client` is marked operator-managed** with
  `metadata.materialize_managed: true`. ory-selfservice treats any client without the
  marker as self-registered (dynamic client registration) and grants it only
  `dcr_audience_allowlist` audiences, because Hydra lets a self-registered client declare
  any audience it likes. **Any other OAuth2 client you create through Hydra's admin API or
  as an `OAuth2Client` needs the same marker**, or it loses any audience that is not on the
  allow-list. Dynamic client registration cannot set `metadata`, and Hydra Maester runs in
  single-namespace mode, so only `OAuth2Client` resources in the Ory namespace reach Hydra.
- **Hydra enforces PKCE for public clients** (`oauth2.pkce.enforced_for_public_clients`).
  The console (oidc-client-ts) sends PKCE by default and MCP clients are required to.
- **Secrets reach the UI as files.** The pod mounts the `<name>-secrets` Secret read-only
  and sets `COOKIE_SECRET_FILE`, `CSRF_COOKIE_SECRET_FILE` and `TOKEN_HOOK_API_KEY_FILE`
  instead of passing the values as env vars, which are readable through `/proc`,
  `kubectl exec env` and crash dumps. The pod also no longer mounts a service-account
  token.
- **`public_url`** (new) sets `PUBLIC_URL`; `ory-stack` passes the UI's own URL, so the
  service never builds URLs or cookie decisions from a request's `Host` header.

## Secret length requirement

`COOKIE_SECRET` and `CSRF_COOKIE_SECRET` must now be **at least 32 characters**. The
secrets this module generates (when `cookie_secret` / `csrf_cookie_secret` are left null)
are already 32 characters, so nothing to do. Callers passing their own shorter secrets
must rotate them to 32+ characters before upgrading, or the new pods will fail to start.
Rotating either secret invalidates existing browser sessions (users sign in again).

## New variables

| Variable | Default | Purpose |
|---|---|---|
| `screens_enabled` | `true` | `false` puts the service in consent-only mode. |
| `claim_metadata_public_id_token` | `["groups"]` | `metadata_public` keys copied onto every id_token. |
| `claim_metadata_public_access_token` | `["groups"]` | `metadata_public` keys copied onto every access token. |
| `claim_traits_id_token` | `[]` | Identity traits copied onto every id_token. |
| `claim_traits_access_token` | `[]` | Identity traits copied onto every access token. |
| `token_hook_enabled` | `false` | Serve `POST /hooks/token`, Hydra's token hook. |
| `token_hook_api_key` | `null` | Shared key for the hook; generated (48 chars) when null and the hook is on. |
| `log_level` | `"info"` | One of `fatal`, `error`, `warn`, `info`, `debug`, `trace`. |
| `log_redact_pii` | `true` | Hash emails and group names in logs. |
| `token_hook_max_auth_age_seconds` | `0` | Refuse user tokens once the last IdP sign-in is older than this. |
| `remember_consent_for_seconds` | `3600` | How long a granted consent is remembered. |
| `public_url` | `null` | The UI's browser-facing origin; set by `ory-stack`. |
| `kratos_cookie_domain` | `null` | Parent domain of the UI and Kratos hosts; needed for SSO when they differ (below). |

`kratos_public_url` and `kratos_browser_url` are now optional, because consent-only mode
does not talk to the Kratos public API. `kratos_public_url` is still required (enforced by
a precondition) when `screens_enabled` is true.

### SSO with the UI and Kratos on different hostnames

The new image serves the Kratos API to the browser through its own origin (`/.ory/...`)
rather than having the browser call Kratos directly. Kratos sets its SSO continuity
cookie (`ory_kratos_continuity`) without a Domain, so through the UI it would land
host-only on the UI's hostname, and the IdP callback, which goes to Kratos's own
hostname, would fail with "no resumable session found". `kratos_cookie_domain` makes the
UI scope that cookie to the shared parent domain, the same one Kratos's `cookies.domain`
uses.

`ory-stack` passes its `kratos_cookie_domain`, which it requires whenever the UI and
Kratos are on different hosts; the UI keeps its own hostname in both per-service and
single-domain mode, so with the UI deployed it always is. Standalone users of this module
must set it themselves whenever the UI and the Kratos browser host differ. The service
refuses to start if the value does not cover both hosts.

### Consent-only mode

Set `screens_enabled = false` (or, via `ory-stack`, `selfservice_ui_mode = "consent-only"`)
when another app - typically the Materialize console - owns the user-facing flows. The
service then serves only Hydra's consent endpoint, the health endpoints and, when enabled,
the token hook. In that mode Hydra's `login_url` and Kratos's `selfservice.flows.login.ui_url`
must point at that app; `ory-stack` exposes this as `var.login_url` and requires it in
consent-only mode.

### Token hook

With `token_hook_enabled = true` the service serves `POST /hooks/token` and Hydra calls it
on every token issuance, so claims are refreshed from Kratos on refresh-token grants rather
than frozen at consent time. Hydra has to be told about the hook:

```hcl
module "ory_hydra" {
  # ...
  token_hook = {
    url            = module.ory_selfservice_ui.token_hook_url
    api_key_header = module.ory_selfservice_ui.token_hook_api_key_header
    api_key        = module.ory_selfservice_ui.token_hook_api_key
  }
}
```

which renders into Hydra's config as:

```yaml
oauth2:
  token_hook:
    url: https://ory-selfservice-ui.ory.svc.cluster.local:3000/hooks/token
    auth:
      type: api_key
      config:
        in: header
        name: X-Token-Hook-Api-Key
```

The key itself is not in that config: the chart renders `hydra.config` into a ConfigMap,
which anyone with the built-in `view` role can read. `ory-hydra` stores it in a
`<release>-token-hook` Secret and hands it to Hydra as `OAUTH2_TOKEN_HOOK_AUTH_CONFIG_VALUE`.
Setting `deployment.extraEnv` in `hydra_helm_values` replaces that env var, so add the
module's entry back if you override it.

Through `ory-stack` this is a single toggle: `selfservice_ui_token_hook_enabled = true`.

Hydra calls the hook over the UI's own TLS listener (the UI terminates TLS with the
`ory-selfservice-ui-tls` certificate), so the URL's host must be in that certificate and
Hydra must trust its issuer. `ory-stack` picks the URL from `cert_issuer_signs_cluster_local`:

- `true` (the self-signed cluster issuer): the certificate gets the in-cluster name
  `ory-selfservice-ui.<namespace>.svc.cluster.local`, Hydra calls that, and Hydra is given
  the certificate's `ca.crt` to trust (`token_hook.ca_secret_name`, added to Hydra's roots
  through `SSL_CERT_DIR`).
- `false`: Hydra calls `https://<ui_fqdn>/hooks/token`, like the other in-cluster callers
  that hairpin through the load balancer, and trusts it through its system roots. A private
  CA that cannot sign cluster.local names also needs its root added to Hydra.

The API key must be at least 32 characters; leave `token_hook_api_key` null to have the
module generate a 48-character one and read it back from the `token_hook_api_key` output.
