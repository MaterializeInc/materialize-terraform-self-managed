# The monitoring stack's namespace and CRDs, installed before anything else in
# the cluster.
#
# The CRDs are the prometheus-operator and grafana-operator definitions that the
# materialize-monitoring chart's custom resources need. Installing them here,
# ahead of Karpenter, cert-manager and the rest, is what lets those charts ship
# their own ServiceMonitors in the same apply: a chart that declares a
# ServiceMonitor before the CRD exists either fails its install or, where it
# checks for the API first, silently leaves the monitor out and never renders it
# again, since Terraform only upgrades a release when its values change.
#
# The release keeps the name and namespace the monitoring module used to give it,
# `mzmon-crds` in the monitoring namespace, so an existing install moves it here
# with a `moved` block rather than reinstalling it. That matters: the CRDs are
# the schema of every PodMonitor, ServiceMonitor and Grafana resource in the
# cluster, and uninstalling them deletes those resources along with them.
#
# The namespace lives here for the same reason. The release metadata has to sit
# in it, and the operator module, which used to create it, is installed far
# later.

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
  timeout   = var.install_timeout

  # CRDs are cluster-scoped; the namespace only holds the release metadata.
  create_namespace = false

  # The provider renders subchart notes by default, unlike `helm install`.
  render_subchart_notes = false

  depends_on = [kubernetes_namespace.monitoring]
}
