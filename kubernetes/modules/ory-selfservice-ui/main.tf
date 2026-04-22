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

          # Tell Node.js to trust the CA that issued the mounted cert. Without this,
          # server-side HTTPS calls from the UI to Kratos/Hydra fail with
          # UNABLE_TO_VERIFY_LEAF_SIGNATURE when they're behind self-signed certs.
          dynamic "env" {
            for_each = local.tls_enabled ? [1] : []
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
