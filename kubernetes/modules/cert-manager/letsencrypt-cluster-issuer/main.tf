locals {
  letsencrypt_staging = var.acme_server == null && !var.acme_server_prod

  acme_server = var.acme_server != null ? var.acme_server : (
    var.acme_server_prod
    ? "https://acme-v02.api.letsencrypt.org/directory"
    : "https://acme-staging-v02.api.letsencrypt.org/directory"
  )

  # The staging issuer has a name of its own, so moving to production changes
  # the issuerRef of every Certificate that uses issuer_name, and cert-manager
  # reissues those certificates from production.
  issuer_name = local.letsencrypt_staging ? "${var.name_prefix}-letsencrypt-staging" : "${var.name_prefix}-letsencrypt"
}

resource "kubectl_manifest" "letsencrypt_cluster_issuer" {
  yaml_body = jsonencode({
    "apiVersion" = "cert-manager.io/v1"
    "kind"       = "ClusterIssuer"
    "metadata" = {
      "name" = local.issuer_name
    }
    "spec" = {
      "acme" = {
        "server" = local.acme_server
        "email"  = var.acme_email
        "privateKeySecretRef" = {
          "name" = "${local.issuer_name}-account-key"
        }
        "solvers" = var.solvers
      }
    }
  })
}
