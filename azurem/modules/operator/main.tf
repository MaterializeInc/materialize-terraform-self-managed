

locals {
  default_helm_values = {
    operator = {
      image = var.orchestratord_version == null ? {} : {
        tag = var.orchestratord_version
      },
      cloudProvider = {
        type   = "azure"
        region = var.location
      }
    }
    observability = {
      podMetrics = {
        enabled = true
      }
    }
    tls = var.use_self_signed_cluster_issuer ? {
      defaultCertificateSpecs = {
        balancerdExternal = {
          dnsNames = [
            "balancerd",
          ]
          issuerRef = {
            name = module.certificates.cluster_issuer_name
            kind = "ClusterIssuer"
          }
        }
        consoleExternal = {
          dnsNames = [
            "console",
          ]
          issuerRef = {
            name = module.certificates.cluster_issuer_name
            kind = "ClusterIssuer"
          }
        }
        internal = {
          issuerRef = {
            name = module.certificates.cluster_issuer_name
            kind = "ClusterIssuer"
          }
        }
      }
    } : {}
    storage = var.enable_disk_support ? {
      storageClass = {
        create      = local.disk_config.create_storage_class
        name        = local.disk_config.storage_class_name
        provisioner = local.disk_config.storage_class_provisioner
        parameters  = local.disk_config.storage_class_parameters
      }
    } : {}
  }


  # Requires OpenEBS to be installed
  disk_config = {
    create_storage_class      = var.enable_disk_support ? lookup(var.disk_support_config, "create_storage_class", true) : false
    storage_class_name        = lookup(var.disk_support_config, "storage_class_name", "openebs-lvm-instance-store-ext4")
    storage_class_provisioner = lookup(var.disk_support_config, "storage_class_provisioner", "local.csi.openebs.io")
    storage_class_parameters = lookup(var.disk_support_config, "storage_class_parameters", {
      storage  = "lvm"
      fsType   = "ext4"
      volgroup = "instance-store-vg"
    })
  }
}

resource "kubernetes_namespace" "materialize" {
  metadata {
    name = var.operator_namespace
  }
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = var.monitoring_namespace
  }
}

resource "helm_release" "materialize_operator" {
  name      = var.name_prefix
  namespace = kubernetes_namespace.materialize.metadata[0].name

  repository = var.use_local_chart ? null : var.helm_repository
  chart      = var.helm_chart
  version    = var.use_local_chart ? null : var.operator_version

  values = [
    yamlencode(merge(local.default_helm_values, var.helm_values))
  ]

  depends_on = [kubernetes_namespace.materialize]
}

# Install the metrics-server for monitoring
# Required for the Materialize Console to display cluster metrics
# Defaults to false because AKS provides metrics-server by default
# TODO: we should rather rely on AKS metrics-server instead of installing our own, confirm with team and get rid of this helm release
resource "helm_release" "metrics_server" {
  count = var.install_metrics_server ? 1 : 0

  name       = "${var.name_prefix}-metrics-server"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.metrics_server_version

  # Configuration values based on metrics_server_values
  dynamic "set" {
    for_each = var.metrics_server_values.skip_tls_verification ? [1] : []
    content {
      name  = "args[0]"
      value = "--kubelet-insecure-tls"
    }
  }

  set {
    name  = "metrics.enabled"
    value = var.metrics_server_values.metrics_enabled
  }

  depends_on = [
    kubernetes_namespace.monitoring
  ]
}
