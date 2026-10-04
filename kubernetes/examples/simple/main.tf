# Self-managed Materialize on any existing cluster reachable through a
# kubeconfig, with no cloud infrastructure. Bring your own PostgreSQL (metadata)
# and S3-compatible storage (persist) and pass their URLs as variables.

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
      # The materialize-instance module only allows egress to kube-system and the
      # API server; on enforcing CNIs these chart policies let environmentd reach
      # the backends, as in the cloud operator modules.
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
