# TODO: Move to a Helm chart when Ory publishes an official Polis chart.
# Polis does not have an official Helm chart yet, so we deploy using raw
# Kubernetes resources (Deployment + Service).

resource "kubernetes_namespace" "polis" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
  }
}

resource "random_password" "jackson_api_keys" {
  count   = var.jackson_api_keys == null ? 1 : 0
  length  = 32
  special = false
}

resource "random_password" "nextauth_secret" {
  count   = var.nextauth_secret == null ? 1 : 0
  length  = 32
  special = false
}

locals {
  namespace        = var.create_namespace ? kubernetes_namespace.polis[0].metadata[0].name : var.namespace
  jackson_api_keys = var.jackson_api_keys != null ? var.jackson_api_keys : random_password.jackson_api_keys[0].result
  nextauth_secret  = var.nextauth_secret != null ? var.nextauth_secret : random_password.nextauth_secret[0].result

  image = "${var.image_registry}/${var.image_repository}:${var.image_tag}"

  labels = {
    "app.kubernetes.io/name"       = "polis"
    "app.kubernetes.io/instance"   = var.name
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/part-of"    = "ory"
  }
}

resource "kubernetes_secret" "polis" {
  metadata {
    name      = "${var.name}-config"
    namespace = local.namespace
    labels    = local.labels
  }

  data = {
    DB_URL           = var.dsn
    JACKSON_API_KEYS = local.jackson_api_keys
    NEXTAUTH_SECRET  = local.nextauth_secret
  }
}

resource "kubernetes_deployment" "polis" {
  metadata {
    name      = var.name
    namespace = local.namespace
    labels    = local.labels
  }

  spec {
    replicas = var.replica_count

    selector {
      match_labels = {
        "app.kubernetes.io/name"     = "polis"
        "app.kubernetes.io/instance" = var.name
      }
    }

    template {
      metadata {
        labels = local.labels
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
          name              = "polis"
          image             = local.image
          image_pull_policy = var.image_pull_policy

          port {
            name           = "http"
            container_port = var.port
            protocol       = "TCP"
          }

          env {
            name  = "PORT"
            value = tostring(var.port)
          }

          env {
            name  = "DB_ENGINE"
            value = "sql"
          }

          env {
            name  = "DB_TYPE"
            value = "postgres"
          }

          env {
            name = "DB_URL"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.polis.metadata[0].name
                key  = "DB_URL"
              }
            }
          }

          env {
            name = "JACKSON_API_KEYS"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.polis.metadata[0].name
                key  = "JACKSON_API_KEYS"
              }
            }
          }

          env {
            name  = "SAML_AUDIENCE"
            value = var.saml_audience
          }

          env {
            name  = "EXTERNAL_URL"
            value = var.external_url
          }

          env {
            name  = "NEXTAUTH_URL"
            value = var.external_url
          }

          env {
            name = "NEXTAUTH_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.polis.metadata[0].name
                key  = "NEXTAUTH_SECRET"
              }
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
              path = "/api/health"
              port = var.port
            }
            # Polis is a NextJS app and can take ~20s on cold start before it
            # finishes DB migrations and is ready to answer /api/health, so the
            # liveness probe needs enough initial delay to avoid a crash loop.
            initial_delay_seconds = 30
            period_seconds        = 30
          }

          readiness_probe {
            http_get {
              path = "/api/health"
              port = var.port
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_namespace.polis,
    kubernetes_secret.polis,
  ]
}

resource "kubernetes_service" "polis" {
  metadata {
    name      = var.name
    namespace = local.namespace
    labels    = local.labels
  }

  spec {
    type = "ClusterIP"

    selector = {
      "app.kubernetes.io/name"     = "polis"
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
