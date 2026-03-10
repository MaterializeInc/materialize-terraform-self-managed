resource "kubectl_manifest" "acme_cluster_issuer" {
  yaml_body = jsonencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "${var.name_prefix}-acme"
    }
    spec = {
      acme = {
        email  = var.acme_email
        server = var.acme_server
        privateKeySecretRef = {
          name = "${var.name_prefix}-acme-account-key"
        }
        solvers = [var.solver_config]
      }
    }
  })
}
