locals {
  acme_server = var.acme_server != null ? var.acme_server : (
    var.acme_server_prod
    ? "https://acme-v02.api.letsencrypt.org/directory"
    : "https://acme-staging-v02.api.letsencrypt.org/directory"
  )
}

resource "kubectl_manifest" "letsencrypt_cluster_issuer" {
  yaml_body = jsonencode({
    "apiVersion" = "cert-manager.io/v1"
    "kind"       = "ClusterIssuer"
    "metadata" = {
      "name" = "${var.name_prefix}-letsencrypt"
    }
    "spec" = {
      "acme" = {
        "server" = local.acme_server
        "email"  = var.acme_email
        "privateKeySecretRef" = {
          "name" = "${var.name_prefix}-letsencrypt-account-key"
        }
        "solvers" = var.solvers
      }
    }
  })
}
