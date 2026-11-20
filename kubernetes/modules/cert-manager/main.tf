resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "cert_manager" {
  # cert-manager is a singleton resource for the cluster,
  # so not using name prefixes here.
  name       = "cert-manager"
  namespace  = kubernetes_namespace.cert_manager.metadata[0].name
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = var.chart_version
  timeout    = var.install_timeout

  set = concat(
    [
      { name = "crds.enabled", value = "true" },
      # One ServiceMonitor across the controller, webhook and cainjector. The
      # chart's metrics Services exist regardless; it does not check for the
      # monitoring.coreos.com API before rendering the monitor.
      { name = "prometheus.servicemonitor.enabled", value = var.enable_service_monitor },
    ],
    # Annotations on cert-manager's Kubernetes service account, which is how a
    # DNS-01 solver gets a cloud identity (GKE Workload Identity, IRSA). Values
    # are set as strings so that one such as "true" stays a string.
    [for k, v in var.service_account_annotations : {
      name  = "serviceAccount.annotations.${replace(k, ".", "\\.")}"
      value = v
      type  = "string"
    }],
    # IRSA and Azure Workload Identity inject credentials when a pod is admitted,
    # and a ServiceAccount change alone rolls nothing, so the controller pods carry
    # a checksum of the annotations and restart when they change.
    length(var.service_account_annotations) > 0 ? [{
      name  = "podAnnotations.checksum/service-account-annotations"
      value = sha256(jsonencode(var.service_account_annotations))
      type  = "string"
    }] : [],
    # Labels on the controller pods, the ones that solve ACME challenges. Azure
    # Workload Identity selects pods by the azure.workload.identity/use label.
    [for k, v in var.pod_labels : {
      name  = "podLabels.${replace(k, ".", "\\.")}"
      value = v
      type  = "string"
    }],
    # Add node selectors for cert-manager pods if provided
    [for k, v in var.node_selector : { name = "nodeSelector.${replace(k, ".", "\\.")}", value = v }],
    [for k, v in var.node_selector : { name = "webhook.nodeSelector.${replace(k, ".", "\\.")}", value = v }],
    [for k, v in var.node_selector : { name = "cainjector.nodeSelector.${replace(k, ".", "\\.")}", value = v }],
    # Add tolerations for cert-manager pods if provided
    [for i, t in var.tolerations : { name = "tolerations[${i}].key", value = t.key }],
    [for i, t in var.tolerations : { name = "tolerations[${i}].operator", value = t.operator }],
    [for i, t in var.tolerations : { name = "tolerations[${i}].value", value = t.value } if t.value != null],
    [for i, t in var.tolerations : { name = "tolerations[${i}].effect", value = t.effect }],
  )

  depends_on = [
    kubernetes_namespace.cert_manager,
  ]
}

