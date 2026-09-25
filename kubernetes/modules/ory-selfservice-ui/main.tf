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

# Only generated when the token hook is on: Hydra authenticates to the hook with
# this key, so an unused one would still churn the Secret and roll the pods.
resource "random_password" "token_hook_api_key" {
  count   = var.token_hook_enabled && var.token_hook_api_key == null ? 1 : 0
  length  = 48
  special = false
}

locals {
  namespace          = var.create_namespace ? kubernetes_namespace.ui[0].metadata[0].name : var.namespace
  cookie_secret      = var.cookie_secret != null ? var.cookie_secret : random_password.cookie_secret[0].result
  csrf_cookie_secret = var.csrf_cookie_secret != null ? var.csrf_cookie_secret : random_password.csrf_cookie_secret[0].result

  token_hook_api_key = (
    !var.token_hook_enabled ? null :
    var.token_hook_api_key != null ? var.token_hook_api_key : random_password.token_hook_api_key[0].result
  )

  tls_enabled   = var.tls_cert_secret_name != null
  tls_mount_dir = "/etc/selfservice-ui/tls"
  probe_scheme  = local.tls_enabled ? "HTTPS" : "HTTP"

  image = "${var.image_repository}:${var.image_tag}"

  service_url = "${local.tls_enabled ? "https" : "http"}://${var.name}.${local.namespace}.svc.cluster.local:${var.port}"

  # app.kubernetes.io/name stays "kratos-selfservice-ui-node" even though the
  # image is now Materialize's ory-selfservice: it is part of the Deployment's
  # immutable selector (see below) and of ory-stack's LoadBalancer selector.
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
  secret_checksum = sha256(jsonencode(local.secret_data))

  secret_data = merge(
    {
      COOKIE_SECRET      = local.cookie_secret
      CSRF_COOKIE_SECRET = local.csrf_cookie_secret
    },
    local.token_hook_api_key != null ? { TOKEN_HOOK_API_KEY = local.token_hook_api_key } : {},
  )
}

resource "kubernetes_secret" "secrets" {
  metadata {
    name      = "${var.name}-secrets"
    namespace = local.namespace
    labels    = local.labels
  }

  data = local.secret_data

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

    # Do not touch these labels. A Deployment's selector is immutable, so
    # changing it forces a replacement of the Deployment (and its pods) rather
    # than an in-place rolling upgrade, which is the whole point of the
    # drop-in image swap from oryd/kratos-selfservice-ui-node to
    # ory-selfservice. ory-stack's selfservice UI LoadBalancer selects on the
    # same app.kubernetes.io/name value, so renaming it here would also orphan
    # that Service.
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

        security_context {
          run_as_non_root = true
          run_as_user     = 10000
          run_as_group    = 10000
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        dynamic "volume" {
          for_each = local.tls_enabled ? [1] : []
          content {
            name = "tls-cert"
            secret {
              secret_name = var.tls_cert_secret_name
            }
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

          # Metrics stay on their own port: the public Service only targets
          # var.port, so they are reachable from inside the cluster only.
          dynamic "port" {
            for_each = var.metrics_port != null ? [1] : []
            content {
              name           = "metrics"
              container_port = var.metrics_port
              protocol       = "TCP"
            }
          }

          dynamic "volume_mount" {
            for_each = local.tls_enabled ? [1] : []
            content {
              name       = "tls-cert"
              mount_path = local.tls_mount_dir
              read_only  = true
            }
          }

          env {
            name  = "PORT"
            value = tostring(var.port)
          }

          # Only emitted when set: consent-only deployments never call the
          # Kratos public API, and an empty value would fail the service's own
          # config validation.
          dynamic "env" {
            for_each = var.kratos_public_url != null ? [1] : []
            content {
              name  = "KRATOS_PUBLIC_URL"
              value = var.kratos_public_url
            }
          }

          dynamic "env" {
            for_each = coalesce(var.kratos_browser_url, var.kratos_public_url, "") != "" ? [1] : []
            content {
              name  = "KRATOS_BROWSER_URL"
              value = coalesce(var.kratos_browser_url, var.kratos_public_url)
            }
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

          env {
            name  = "CSRF_COOKIE_NAME"
            value = var.csrf_cookie_name
          }

          # false puts the service in consent-only mode: just Hydra's consent
          # endpoint, the health endpoints and (when enabled) the token hook.
          env {
            name  = "SELF_SERVICE_SCREENS_ENABLED"
            value = tostring(var.screens_enabled)
          }

          # Identity traits copied onto the issued tokens. This is what makes
          # MCP OAuth work; pair with ory-stack's allowed_top_level_claims so
          # the claims sit top-level rather than under Hydra's ext.
          env {
            name  = "CLAIM_TRAITS_ID_TOKEN"
            value = join(",", var.claim_traits_id_token)
          }

          env {
            name  = "CLAIM_TRAITS_ACCESS_TOKEN"
            value = join(",", var.claim_traits_access_token)
          }

          env {
            name  = "TOKEN_HOOK_ENABLED"
            value = tostring(var.token_hook_enabled)
          }

          env {
            name  = "LOG_LEVEL"
            value = var.log_level
          }

          env {
            name  = "LOG_REDACT_PII"
            value = tostring(var.log_redact_pii)
          }

          dynamic "env" {
            for_each = var.metrics_port != null ? [1] : []
            content {
              name  = "METRICS_PORT"
              value = tostring(var.metrics_port)
            }
          }

          # Audience for self-registered (DCR) clients; see the variables.
          dynamic "env" {
            for_each = length(var.dcr_audience_allowlist) > 0 ? [1] : []
            content {
              name  = "DCR_AUDIENCE_ALLOWLIST"
              value = join(",", var.dcr_audience_allowlist)
            }
          }

          dynamic "env" {
            for_each = length(var.dcr_default_audience) > 0 ? [1] : []
            content {
              name  = "DCR_DEFAULT_AUDIENCE"
              value = join(",", var.dcr_default_audience)
            }
          }

          env {
            name  = "REMEMBER_CONSENT_SESSION_FOR_SECONDS"
            value = tostring(var.remember_consent_for_seconds)
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
            for_each = local.token_hook_api_key != null ? [1] : []
            content {
              name = "TOKEN_HOOK_API_KEY"
              value_from {
                secret_key_ref {
                  name = kubernetes_secret.secrets.metadata[0].name
                  key  = "TOKEN_HOOK_API_KEY"
                }
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

          # The image writes nothing at runtime (the old consent.js patch was
          # the only reason it ever needed a writable path), so it runs with a
          # read-only root filesystem and no capabilities.
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            run_as_non_root            = true
            run_as_user                = 10000
            run_as_group               = 10000
            capabilities {
              drop = ["ALL"]
            }
            seccomp_profile {
              type = "RuntimeDefault"
            }
          }
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = !var.screens_enabled || var.kratos_public_url != null
      error_message = "kratos_public_url must be set when screens_enabled is true; only consent-only mode (screens_enabled = false) can leave it null."
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
