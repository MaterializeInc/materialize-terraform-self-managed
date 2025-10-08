resource "kubernetes_manifest" "self_signed_cluster_issuer" {
  manifest = {
    "apiVersion" = "cert-manager.io/v1"
    "kind"       = "ClusterIssuer"
    "metadata" = {
      "name" = "${var.name_prefix}-self-signed"
    }
    "spec" = {
      "selfSigned" = {}
    }
  }
}

resource "kubernetes_manifest" "self_signed_root_ca_certificate" {
  manifest = {
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
  }

  depends_on = [
    kubernetes_manifest.self_signed_cluster_issuer,
  ]
}

resource "kubernetes_manifest" "root_ca_cluster_issuer" {
  manifest = {
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
  }

  depends_on = [
    kubernetes_manifest.self_signed_root_ca_certificate,
  ]
}
