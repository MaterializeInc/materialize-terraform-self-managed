# First-cut Ory Talos module. Talos is currently in early access and has no
# published Helm chart in the preview docs, so this module deploys it as a
# raw Deployment + Service + Secret. Once Ory publishes a chart (or we
# confirm one already exists at an OCI registry we have access to), swap
# this to a helm_release in the same shape as the ory-polis module.
#
# Coexistence with Hydra: Talos and Hydra are independent issuers by default.
# A downstream OIDC consumer (Materialize, etc.) that trusts a single issuer
# URL can only validate one of them at a time. Per Ory guidance, the
# recommended pattern is to set var.credentials_issuer to the same URL Hydra
# publishes as its issuer and have Talos sign with the same JWK set via
# var.signing_keys_urls; both services then mint JWTs that the same
# downstream accepts. The alternative is fronting both with Oathkeeper at
# the edge and re-issuing a common token; that's heavier and out of scope
# for this module.

resource "kubernetes_namespace" "talos" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
  }
}

resource "random_password" "default_secret" {
  count   = var.default_secret == null ? 1 : 0
  length  = 32
  special = false
}

resource "random_password" "hmac_secret" {
  count   = var.hmac_secret == null ? 1 : 0
  length  = 32
  special = false
}

resource "random_password" "pagination_secret" {
  count   = var.pagination_secret == null ? 1 : 0
  length  = 32
  special = false
}

locals {
  namespace = var.create_namespace ? kubernetes_namespace.talos[0].metadata[0].name : var.namespace

  default_secret    = var.default_secret != null ? var.default_secret : random_password.default_secret[0].result
  hmac_secret       = var.hmac_secret != null ? var.hmac_secret : random_password.hmac_secret[0].result
  pagination_secret = var.pagination_secret != null ? var.pagination_secret : random_password.pagination_secret[0].result

  image = "${var.image_registry}/${var.image_repository}:${var.image_tag}"

  labels = {
    "app.kubernetes.io/name"       = "talos"
    "app.kubernetes.io/instance"   = var.name
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/part-of"    = "ory"
  }

  # Secret data Talos reads from env at startup. Kept in a Kubernetes Secret
  # so the raw values do not appear on the Deployment manifest.
  secret_data = merge(
    {
      TALOS_DB_DSN                     = var.dsn
      TALOS_SECRETS_DEFAULT_CURRENT    = local.default_secret
      TALOS_SECRETS_HMAC_CURRENT       = local.hmac_secret
      TALOS_SECRETS_PAGINATION_CURRENT = local.pagination_secret
      TALOS_CREDENTIALS_ISSUER         = var.credentials_issuer
    },
    var.signing_key_id != null ? {
      TALOS_CREDENTIALS_DERIVED_TOKENS_JWT_SIGNING_KEY_ID = var.signing_key_id
    } : {},
    length(var.signing_keys_urls) > 0 ? {
      # Talos accepts comma-separated values for array config keys.
      TALOS_CREDENTIALS_DERIVED_TOKENS_JWT_SIGNING_KEYS_URLS = join(",", var.signing_keys_urls)
    } : {},
  )

  # Hash of the secret data so the pod template rolls when any value changes.
  # Kubernetes does not automatically restart pods when an envFrom-referenced
  # secret changes.
  secret_checksum = sha256(jsonencode(local.secret_data))
}

resource "kubernetes_secret" "talos" {
  metadata {
    name      = "${var.name}-config"
    namespace = local.namespace
    labels    = local.labels
  }

  data = local.secret_data
}

resource "kubernetes_deployment" "talos" {
  metadata {
    name      = var.name
    namespace = local.namespace
    labels    = local.labels
  }

  spec {
    replicas = var.replica_count

    selector {
      match_labels = {
        "app.kubernetes.io/name"     = "talos"
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
        dynamic "image_pull_secrets" {
          for_each = var.image_pull_secrets
          content {
            name = image_pull_secrets.value
          }
        }

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

        container {
          name              = "talos"
          image             = local.image
          image_pull_policy = var.image_pull_policy

          port {
            name           = "http"
            container_port = var.http_port
            protocol       = "TCP"
          }

          port {
            name           = "metrics"
            container_port = var.metrics_port
            protocol       = "TCP"
          }

          env {
            name  = "TALOS_SERVE_HTTP_PORT"
            value = tostring(var.http_port)
          }

          env {
            name  = "TALOS_SERVE_METRICS_PORT"
            value = tostring(var.metrics_port)
          }

          env {
            name  = "TALOS_LOG_LEVEL"
            value = var.log_level
          }

          env {
            name  = "TALOS_LOG_FORMAT"
            value = var.log_format
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.talos.metadata[0].name
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
              path = "/health/alive"
              port = var.http_port
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/health/ready"
              port = var.http_port
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "talos" {
  metadata {
    name      = var.name
    namespace = local.namespace
    labels    = local.labels
  }

  spec {
    type = "ClusterIP"

    selector = {
      "app.kubernetes.io/name"     = "talos"
      "app.kubernetes.io/instance" = var.name
    }

    port {
      name        = "http"
      port        = var.http_port
      target_port = var.http_port
      protocol    = "TCP"
    }

    port {
      name        = "metrics"
      port        = var.metrics_port
      target_port = var.metrics_port
      protocol    = "TCP"
    }
  }
}
