resource "kubectl_manifest" "letsencrypt_cluster_issuer" {
  yaml_body = jsonencode({
    "apiVersion" = "cert-manager.io/v1"
    "kind"       = "ClusterIssuer"
    "metadata" = {
      "name" = "${var.name_prefix}-letsencrypt"
    }
    "spec" = {
      "acme" = {
        "server" = var.acme_server
        "email"  = var.acme_email
        "privateKeySecretRef" = {
          "name" = "${var.name_prefix}-letsencrypt-account-key"
        }
        "solvers" = var.solvers
      }
    }
  })
}
