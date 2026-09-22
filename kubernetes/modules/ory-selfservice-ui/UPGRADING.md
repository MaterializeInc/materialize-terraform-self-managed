# Upgrading the Ory selfservice UI

## Swapping `oryd/kratos-selfservice-ui-node` for `ory-selfservice`

This module now deploys Materialize's own service,
[`ory-selfservice`](https://github.com/MaterializeInc/ory-selfservice), instead of the
upstream `oryd/kratos-selfservice-ui-node` reference UI:

| | before | after |
|---|---|---|
| `image_repository` | `oryd/kratos-selfservice-ui-node` | `ghcr.io/materializeinc/ory-selfservice` |
| `image_tag` | `v25.4.0` | `v0.1.0` |

The image will also be published to Docker Hub as `materialize/ory-selfservice` once it is
public. Air-gapped installs mirror whichever of the two they can reach into their own
registry and point `image_repository` at the mirror.

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
| `claim_traits_id_token` | `["groups"]` | Identity traits copied onto every id_token. |
| `claim_traits_access_token` | `["groups"]` | Identity traits copied onto every access token. |
| `token_hook_enabled` | `false` | Serve `POST /hooks/token`, Hydra's token hook. |
| `token_hook_api_key` | `null` | Shared key for the hook; generated (48 chars) when null and the hook is on. |
| `log_level` | `"info"` | One of `fatal`, `error`, `warn`, `info`, `debug`, `trace`. |
| `log_redact_pii` | `false` | Redact emails and trait values from logs. |
| `remember_consent_for_seconds` | `3600` | How long a granted consent is remembered. |

`kratos_public_url` and `kratos_browser_url` are now optional, because consent-only mode
does not talk to the Kratos public API. `kratos_public_url` is still required (enforced by
a precondition) when `screens_enabled` is true.

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
        value: <token_hook_api_key>
```

Through `ory-stack` this is a single toggle: `selfservice_ui_token_hook_enabled = true`.

Hydra calls the hook over the UI's own TLS listener (the UI terminates TLS with the
`ory-selfservice-ui-tls` certificate), so **Hydra must trust that certificate**. With the
self-signed cluster issuer it does not, so the hook needs a publicly trusted certificate
(or the issuing CA added to Hydra's trust store) before it can be turned on.

The API key must be at least 32 characters; leave `token_hook_api_key` null to have the
module generate a 48-character one and read it back from the `token_hook_api_key` output.
