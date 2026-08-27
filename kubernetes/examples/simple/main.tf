# Self-managed Materialize on an existing Kubernetes cluster -- any cluster
# reachable through a kubeconfig, without cloud-provider infrastructure. You
# bring the two backends (PostgreSQL for metadata, S3-compatible storage for
# persist) and pass their connection URLs as variables. The operator is
# installed straight from the Helm chart, whose defaults already target a
# local/generic deployment.

module "cert_manager" {
  source = "../../modules/cert-manager"
}

module "self_signed_cluster_issuer" {
  source = "../../modules/self-signed-cluster-issuer"

  name_prefix = var.name_prefix

  depends_on = [module.cert_manager]
}

resource "helm_release" "materialize_operator" {
  name             = "materialize-operator"
  namespace        = "materialize"
  create_namespace = true

  repository = var.use_local_chart ? null : "https://materializeinc.github.io/materialize/"
  chart      = var.helm_chart
  version    = var.use_local_chart ? null : var.operator_version

  # Helm's default 300s can be eaten by the orchestratord image pull plus the
  # webhook certificate on a cold cluster.
  timeout = 600

  values = [
    yamlencode({
      operator = merge(
        # The materialize-instance module creates v1 CRs; the chart installs
        # only v1alpha1 by default. The v1 conversion webhook needs a
        # certificate from cert-manager.
        { args = { installV1CRD = true } },
        var.orchestratord_version == null ? {} : { image = { tag = var.orchestratord_version } },
      )
      # The materialize-instance module's own policies only allow egress to
      # kube-system and the API server; on enforcing CNIs these chart-level
      # allow policies are what let environmentd reach the backends. Mirrors
      # the cloud operator modules.
      networkPolicies = {
        enabled  = true
        internal = { enabled = true }
        ingress  = { enabled = true, cidrs = ["0.0.0.0/0"] }
        egress   = { enabled = true, cidrs = ["0.0.0.0/0"] }
      }
    })
  ]

  depends_on = [module.cert_manager]
}

resource "random_password" "external_login_password_mz_system" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

module "materialize_instance" {
  source = "../../modules/materialize-instance"

  instance_name        = "main"
  instance_namespace   = "materialize-environment"
  environmentd_version = var.environmentd_version
  license_key          = var.license_key

  metadata_backend_url = var.metadata_backend_url
  persist_backend_url  = var.persist_backend_url

  authenticator_kind                = "Password"
  external_login_password_mz_system = random_password.external_login_password_mz_system.result

  issuer_ref = {
    name = module.self_signed_cluster_issuer.issuer_name
    kind = "ClusterIssuer"
  }

  depends_on = [
    helm_release.materialize_operator,
    module.self_signed_cluster_issuer,
  ]
}
