resource "kubernetes_namespace" "cert_manager" {
  count = var.install_cert_manager ? 1 : 0

  metadata {
    name = var.cert_manager_namespace
  }
}

resource "helm_release" "cert_manager" {
  count = var.install_cert_manager ? 1 : 0

  # cert-manager is a singleton resource for the cluster,
  # so not using name prefixes here.
  name       = "cert-manager"
  namespace  = kubernetes_namespace.cert_manager[0].metadata[0].name
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = var.cert_manager_chart_version
  timeout    = var.cert_manager_install_timeout

  set {
    name  = "crds.enabled"
    value = "true"
  }

  # Add tolerations for cert-manager pods if provided
  dynamic "set" {
    for_each = length(var.cert_manager_tolerations) > 0 ? range(length(var.cert_manager_tolerations)) : []
    content {
      name  = "tolerations[${set.value}].key"
      value = var.cert_manager_tolerations[set.value].key
    }
  }

  dynamic "set" {
    for_each = length(var.cert_manager_tolerations) > 0 ? range(length(var.cert_manager_tolerations)) : []
    content {
      name  = "tolerations[${set.value}].operator"
      value = var.cert_manager_tolerations[set.value].operator
    }
  }

  dynamic "set" {
    for_each = length(var.cert_manager_tolerations) > 0 ? [
      for i, toleration in var.cert_manager_tolerations : i
      if toleration.value != null
    ] : []
    content {
      name  = "tolerations[${set.value}].value"
      value = var.cert_manager_tolerations[set.value].value
    }
  }

  dynamic "set" {
    for_each = length(var.cert_manager_tolerations) > 0 ? range(length(var.cert_manager_tolerations)) : []
    content {
      name  = "tolerations[${set.value}].effect"
      value = var.cert_manager_tolerations[set.value].effect
    }
  }

  depends_on = [
    kubernetes_namespace.cert_manager,
  ]
}

resource "kubernetes_manifest" "self_signed_cluster_issuer" {
  # only create these after cert manager is installed
  count = var.use_self_signed_cluster_issuer ? 1 : 0

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

  depends_on = [
    helm_release.cert_manager,
  ]
}

resource "kubernetes_manifest" "self_signed_root_ca_certificate" {
  count = var.use_self_signed_cluster_issuer ? 1 : 0

  manifest = {
    "apiVersion" = "cert-manager.io/v1"
    "kind"       = "Certificate"
    "metadata" = {
      "name"      = "${var.name_prefix}-self-signed-ca"
      "namespace" = var.cert_manager_namespace
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
    helm_release.cert_manager,
    kubernetes_manifest.self_signed_cluster_issuer,
  ]
}

resource "kubernetes_manifest" "root_ca_cluster_issuer" {
  count = var.use_self_signed_cluster_issuer ? 1 : 0

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
    helm_release.cert_manager,
    kubernetes_manifest.self_signed_root_ca_certificate,
  ]
}
