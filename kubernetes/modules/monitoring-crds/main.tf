# The monitoring namespace and the prometheus/grafana-operator CRDs, installed
# before everything else so other charts can ship ServiceMonitors in the same
# apply. A chart rendered before the CRD exists fails, or silently drops the
# monitor and never renders it until its values change.
#
# Keep the release name and namespace (`mzmon-crds` in the monitoring namespace)
# so existing installs move here with a `moved` block; a reinstall uninstalls
# first and can fail on the name still in use.

resource "kubernetes_namespace" "monitoring" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
  }
}

resource "helm_release" "crds" {
  count = var.install_crds ? 1 : 0

  name      = "mzmon-crds"
  namespace = var.namespace
  chart     = "${var.chart_registry}/materialize-monitoring-crds"
  version   = var.chart_version

  # CRDs are cluster-scoped; the namespace only holds the release metadata.
  create_namespace = false

  # The provider renders subchart notes by default, unlike `helm install`.
  render_subchart_notes = false

  depends_on = [kubernetes_namespace.monitoring]
}
