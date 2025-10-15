resource "kubectl_manifest" "self_signed_cluster_issuer" {
  yaml_body = jsonencode({
    "apiVersion" = "cert-manager.io/v1"
    "kind"       = "ClusterIssuer"
    "metadata" = {
      "name" = "${var.name_prefix}-self-signed"
    }
    "spec" = {
      "selfSigned" = {}
    }
  })
}

resource "kubectl_manifest" "self_signed_root_ca_certificate" {
  yaml_body = jsonencode({
    "apiVersion" = "cert-manager.io/v1"
    "kind"       = "Certificate"
    "metadata" = {
      "name"      = "${var.name_prefix}-self-signed-ca"
      "namespace" = var.namespace
    }
    "spec" = {
      "isCA"       = true
      "commonName" = "${var.name_prefix}-self-signed-ca"
      "secretName" = "${var.name_prefix}-root-ca"
      "privateKey" = {
        "algorithm"      = "RSA"
        "encoding"       = "PKCS8"
        "size"           = 4096
        "rotationPolicy" = "Always"
      }
      "issuerRef" = {
        "name"  = "${var.name_prefix}-self-signed"
        "kind"  = "ClusterIssuer"
        "group" = "cert-manager.io"
      }
    }
  })

  depends_on = [
    kubectl_manifest.self_signed_cluster_issuer,
  ]
}

resource "kubectl_manifest" "root_ca_cluster_issuer" {
  yaml_body = jsonencode({
    "apiVersion" = "cert-manager.io/v1"
    "kind"       = "ClusterIssuer"
    "metadata" = {
      "name" = "${var.name_prefix}-root-ca"
    }
    "spec" = {
      "ca" = {
        "secretName" = "${var.name_prefix}-root-ca"
      }
    }
  })

  depends_on = [
    kubectl_manifest.self_signed_root_ca_certificate,
  ]
}
