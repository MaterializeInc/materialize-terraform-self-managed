resource "kubernetes_namespace" "ui" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
  }
}

resource "random_password" "cookie_secret" {
  count   = var.cookie_secret == null ? 1 : 0
  length  = 32
  special = false
}

resource "random_password" "csrf_cookie_secret" {
  count   = var.csrf_cookie_secret == null ? 1 : 0
  length  = 32
  special = false
}

locals {
  namespace          = var.create_namespace ? kubernetes_namespace.ui[0].metadata[0].name : var.namespace
  cookie_secret      = var.cookie_secret != null ? var.cookie_secret : random_password.cookie_secret[0].result
  csrf_cookie_secret = var.csrf_cookie_secret != null ? var.csrf_cookie_secret : random_password.csrf_cookie_secret[0].result

  tls_enabled   = var.tls_cert_secret_name != null
  tls_mount_dir = "/etc/selfservice-ui/tls"
  probe_scheme  = local.tls_enabled ? "HTTPS" : "HTTP"

  image = "${var.image_repository}:${var.image_tag}"

  labels = {
    "app.kubernetes.io/name"       = "kratos-selfservice-ui-node"
    "app.kubernetes.io/instance"   = var.name
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/part-of"    = "ory"
  }

  # Hash of the secret values so the pod template rolls when any of them
  # change. Kubernetes does not automatically restart pods when a referenced
  # Secret's contents change. The upstream Hydra and Kratos Helm charts emit
  # an equivalent annotation themselves; this module is raw resources so we
  # have to do it by hand.
  secret_checksum = sha256(jsonencode({
    COOKIE_SECRET      = local.cookie_secret
    CSRF_COOKIE_SECRET = local.csrf_cookie_secret
  }))

  # Patch the consent handler so groups + email land on the access token (not
  # just the id_token) and the audience is granted from the client's config.
  # Clients with no audience (e.g. from dynamic client registration) get
  # default_access_token_audience written onto the client before the grant, so
  # refreshes, which Hydra checks against the client's audience, keep working.
  # This is what makes MCP OAuth work; pair with ory-stack's
  # allowed_top_level_claims so the claims sit top-level, not under Hydra's ext.
  # initContainer because the main container is non-root; patched file is mounted
  # over the original.
  consent_claims_patch_script = <<-EOT
    set -eu
    node -e '
      const fs = require("fs");
      const src = fs.readFileSync("/usr/src/app/lib/routes/consent.js", "utf8");
      const inject = "    if (identity.traits && identity.traits.groups) { session.id_token.groups = identity.traits.groups; session.access_token.groups = identity.traits.groups; } var mzEmail = (identity.traits && identity.traits.email) ? identity.traits.email : null; if (!mzEmail && Array.isArray(identity.verifiable_addresses)) { var mzA = identity.verifiable_addresses.filter(function (x) { return x && x.via === \"email\"; })[0]; if (mzA) mzEmail = mzA.value; } if (mzEmail) { session.access_token.email = mzEmail; if (!session.id_token.email) session.id_token.email = mzEmail; }\n    ";
      const idx = src.lastIndexOf("return session;");
      if (idx < 0) throw new Error("consent.js: session pattern not found");
      var out = src.slice(0, idx) + inject + src.slice(idx);
      const needle = "grant_access_token_audience: body.requested_access_token_audience";
      if (!out.includes(needle)) throw new Error("consent.js: audience pattern not found");
      out = out.split(needle).join("grant_access_token_audience: ((body.requested_access_token_audience && body.requested_access_token_audience.length) ? body.requested_access_token_audience : ((body.client && body.client.audience) || []))");
      const accepts = out.match(/oauth2\s*\.acceptOAuth2ConsentRequest\(/g) || [];
      if (accepts.length !== 2) throw new Error("consent.js: expected 2 acceptOAuth2ConsentRequest calls, found " + accepts.length);
      out = out.replace(/oauth2\s*\.acceptOAuth2ConsentRequest\(/g, "mzAcceptConsent(oauth2, body, ");
      const helper = "var mzDefaultAudience = (function () { try { return JSON.parse(process.env.MZ_DEFAULT_ACCESS_TOKEN_AUDIENCE || \"[]\"); } catch (e) { return []; } })();\nfunction mzAcceptConsent(oauth2, body, params) { var client = body.client || {}; var granted = params.acceptOAuth2ConsentRequest.grant_access_token_audience || []; if (granted.length || !mzDefaultAudience.length || !client.client_id) return oauth2.acceptOAuth2ConsentRequest(params); return oauth2.patchOAuth2Client({ id: client.client_id, jsonPatch: [{ op: \"add\", path: \"/audience\", value: mzDefaultAudience }] }).then(function () { params.acceptOAuth2ConsentRequest.grant_access_token_audience = mzDefaultAudience; return oauth2.acceptOAuth2ConsentRequest(params); }); }\n";
      const anchor = "var pkg_1 = require(\"../pkg\");";
      if (!out.includes(anchor)) throw new Error("consent.js: require anchor not found");
      out = out.replace(anchor, anchor + "\n" + helper);
      fs.writeFileSync("/consent-patched/consent.js", out);
      console.error("consent.js: claims + audience patch applied");
    '
  EOT
}

resource "kubernetes_secret" "secrets" {
  metadata {
    name      = "${var.name}-secrets"
    namespace = local.namespace
    labels    = local.labels
  }

  data = {
    COOKIE_SECRET      = local.cookie_secret
    CSRF_COOKIE_SECRET = local.csrf_cookie_secret
  }

  depends_on = [kubernetes_namespace.ui]
}

resource "kubernetes_deployment" "ui" {
  metadata {
    name      = var.name
    namespace = local.namespace
    labels    = local.labels
  }

  spec {
    replicas = var.replica_count

    selector {
      match_labels = {
        "app.kubernetes.io/name"     = "kratos-selfservice-ui-node"
        "app.kubernetes.io/instance" = var.name
      }
    }

    template {
      metadata {
        labels = local.labels
        annotations = {
          "checksum/config" = local.secret_checksum
        }
      }

      spec {
        dynamic "toleration" {
          for_each = var.tolerations
          content {
            key      = toleration.value.key
            operator = toleration.value.operator
            value    = toleration.value.value
            effect   = toleration.value.effect
          }
        }

        node_selector = var.node_selector

        dynamic "volume" {
          for_each = local.tls_enabled ? [1] : []
          content {
            name = "tls-cert"
            secret {
              secret_name = var.tls_cert_secret_name
            }
          }
        }

        volume {
          name = "consent-patched"
          empty_dir {}
        }

        init_container {
          name    = "patch-consent"
          image   = local.image
          command = ["sh", "-c"]
          args    = [local.consent_claims_patch_script]

          volume_mount {
            name       = "consent-patched"
            mount_path = "/consent-patched"
          }
        }

        container {
          name              = "kratos-selfservice-ui-node"
          image             = local.image
          image_pull_policy = var.image_pull_policy

          port {
            name           = "http"
            container_port = var.port
            protocol       = "TCP"
          }

          dynamic "volume_mount" {
            for_each = local.tls_enabled ? [1] : []
            content {
              name       = "tls-cert"
              mount_path = local.tls_mount_dir
              read_only  = true
            }
          }

          volume_mount {
            name       = "consent-patched"
            mount_path = "/usr/src/app/lib/routes/consent.js"
            sub_path   = "consent.js"
            read_only  = true
          }

          env {
            name  = "PORT"
            value = tostring(var.port)
          }

          env {
            name  = "KRATOS_PUBLIC_URL"
            value = var.kratos_public_url
          }

          env {
            name  = "KRATOS_BROWSER_URL"
            value = var.kratos_browser_url != null ? var.kratos_browser_url : var.kratos_public_url
          }

          env {
            name  = "KRATOS_ADMIN_URL"
            value = var.kratos_admin_url
          }

          env {
            name  = "HYDRA_ADMIN_URL"
            value = var.hydra_admin_url
          }

          env {
            name  = "PROJECT_NAME"
            value = var.project_name
          }

          dynamic "env" {
            for_each = length(var.default_access_token_audience) > 0 ? [1] : []
            content {
              name  = "MZ_DEFAULT_ACCESS_TOKEN_AUDIENCE"
              value = jsonencode(var.default_access_token_audience)
            }
          }

          env {
            name  = "CSRF_COOKIE_NAME"
            value = var.csrf_cookie_name
          }

          env {
            name = "COOKIE_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.secrets.metadata[0].name
                key  = "COOKIE_SECRET"
              }
            }
          }

          env {
            name = "CSRF_COOKIE_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.secrets.metadata[0].name
                key  = "CSRF_COOKIE_SECRET"
              }
            }
          }

          dynamic "env" {
            for_each = var.disable_secure_csrf_cookies ? [1] : []
            content {
              name  = "DANGEROUSLY_DISABLE_SECURE_CSRF_COOKIES"
              value = "true"
            }
          }

          dynamic "env" {
            for_each = length(var.trusted_client_ids) > 0 ? [1] : []
            content {
              name  = "TRUSTED_CLIENT_IDS"
              value = join(",", var.trusted_client_ids)
            }
          }

          dynamic "env" {
            for_each = local.tls_enabled ? [1] : []
            content {
              name  = "TLS_CERT_PATH"
              value = "${local.tls_mount_dir}/tls.crt"
            }
          }

          dynamic "env" {
            for_each = local.tls_enabled ? [1] : []
            content {
              name  = "TLS_KEY_PATH"
              value = "${local.tls_mount_dir}/tls.key"
            }
          }

          # Trust the mounted ca.crt for outbound HTTPS to Kratos/Hydra.
          # See var.trust_mounted_ca_cert.
          dynamic "env" {
            for_each = local.tls_enabled && var.trust_mounted_ca_cert ? [1] : []
            content {
              name  = "NODE_EXTRA_CA_CERTS"
              value = "${local.tls_mount_dir}/ca.crt"
            }
          }

          dynamic "env" {
            for_each = var.extra_env
            content {
              name  = env.key
              value = env.value
            }
          }

          resources {
            requests = {
              cpu    = var.resources.requests.cpu
              memory = var.resources.requests.memory
            }
            limits = merge(
              { memory = var.resources.limits.memory },
              var.resources.limits.cpu != null ? { cpu = var.resources.limits.cpu } : {}
            )
          }

          liveness_probe {
            http_get {
              path   = "/health/alive"
              port   = var.port
              scheme = local.probe_scheme
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path   = "/health/ready"
              port   = var.port
              scheme = local.probe_scheme
            }
            initial_delay_seconds = 3
            period_seconds        = 5
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_namespace.ui,
    kubernetes_secret.secrets,
  ]
}

resource "kubernetes_service" "ui" {
  metadata {
    name      = var.name
    namespace = local.namespace
    labels    = local.labels
  }

  spec {
    type = "ClusterIP"

    selector = {
      "app.kubernetes.io/name"     = "kratos-selfservice-ui-node"
      "app.kubernetes.io/instance" = var.name
    }

    port {
      name        = "http"
      port        = var.port
      target_port = var.port
      protocol    = "TCP"
    }
  }
}
