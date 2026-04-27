locals {
  acme_servers = {
    staging    = "https://acme-staging-v02.api.letsencrypt.org/directory"
    production = "https://acme-v02.api.letsencrypt.org/directory"
  }

  acme_server = local.acme_servers[var.acme_environment]

  cloudflare_token_secret_name = "${var.name}-cloudflare-api-token"
  account_key_secret_name      = "${var.name}-account-key"

  dns01_solver = var.dns_provider == "cloudflare" ? {
    dns01 = {
      cloudflare = {
        apiTokenSecretRef = {
          name = local.cloudflare_token_secret_name
          key  = "api-token"
        }
      }
    }
  } : null
}

resource "kubernetes_secret_v1" "cloudflare_api_token" {
  count = var.dns_provider == "cloudflare" ? 1 : 0

  metadata {
    name      = local.cloudflare_token_secret_name
    namespace = var.namespace
  }

  data = {
    "api-token" = var.cloudflare_api_token
  }

  type = "Opaque"

  lifecycle {
    precondition {
      condition     = var.cloudflare_api_token != null
      error_message = "cloudflare_api_token must be set when dns_provider = 'cloudflare'."
    }
  }
}

resource "kubectl_manifest" "cluster_issuer" {
  yaml_body = jsonencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = var.name
    }
    spec = {
      acme = {
        email  = var.email
        server = local.acme_server
        privateKeySecretRef = {
          name = local.account_key_secret_name
        }
        solvers = [
          {
            selector = {
              dnsZones = var.dns_zones
            }
            dns01 = local.dns01_solver.dns01
          },
        ]
      }
    }
  })

  depends_on = [
    kubernetes_secret_v1.cloudflare_api_token,
  ]
}
