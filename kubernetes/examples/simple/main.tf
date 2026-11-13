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

# Let's Encrypt ClusterIssuer for publicly trusted console and balancerd
# certificates, solving ACME DNS-01 challenges in Cloudflare. To use it,
# uncomment this module and the Let's Encrypt settings in
# module.materialize_instance. The solver reads a Cloudflare API token with
# Zone:Read and DNS:Edit from the Secret cloudflare-api-token, key api-token, in
# the cert-manager namespace; any other cert-manager solver works in its place.
# Replace the example.com placeholders. It starts on Let's Encrypt staging as
# <name_prefix>-letsencrypt-staging; set acme_server_prod = true for production
# once staging has issued every certificate.
# See kubernetes/modules/cert-manager/letsencrypt-cluster-issuer/README.md.
#
# module "letsencrypt_cluster_issuer" {
#   source = "../../modules/cert-manager/letsencrypt-cluster-issuer"
#
#   name_prefix = var.name_prefix
#   # Where Let's Encrypt sends notices about the ACME account.
#   acme_email = "platform-team@example.com"
#   # Let's Encrypt staging until a person has checked that it issues every
#   # certificate; then set to true and apply again.
#   acme_server_prod = false
#
#   solvers = [
#     {
#       dns01 = {
#         cloudflare = {
#           apiTokenSecretRef = {
#             name = "cloudflare-api-token"
#             key  = "api-token"
#           }
#         }
#       }
#     }
#   ]
#
#   depends_on = [
#     module.cert_manager,
#   ]
# }

resource "kubernetes_namespace" "materialize_operator" {
  metadata {
    name = "materialize"
  }
}

# The chart's egress-to-environmentd policy selects the operator pods and has
# only egress rules, so Kubernetes applies it to both directions: the operator
# can reach environmentd and nothing else, and nothing can reach the operator.
# On a CNI that enforces NetworkPolicy (kindnet since kind v0.27, Calico,
# Cilium), that cuts it off from the API server and DNS and blocks the v1
# conversion webhook and its health probes on 8001, so it crash-loops and
# never reconciles. Policies are additive; this one gives the operator back
# egress and the ingress its ports need. It has to exist before the release,
# because the release waits for the operator to become ready.
resource "kubernetes_network_policy_v1" "materialize_operator" {
  metadata {
    name      = "allow-materialize-operator"
    namespace = kubernetes_namespace.materialize_operator.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "materialize-operator"
      }
    }
    policy_types = ["Ingress", "Egress"]

    egress {}

    ingress {
      ports {
        protocol = "TCP"
        port     = 8001 # v1 conversion webhook and health probes
      }
      ports {
        protocol = "TCP"
        port     = 3100 # metrics
      }
    }
  }
}

resource "helm_release" "materialize_operator" {
  name      = "materialize-operator"
  namespace = kubernetes_namespace.materialize_operator.metadata[0].name

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

  depends_on = [module.cert_manager, kubernetes_network_policy_v1.materialize_operator]
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
  # With module.letsencrypt_cluster_issuer uncommented, replace issuer_ref
  # above with the settings below. The console and balancerd certificates
  # then come from Let's Encrypt for these public hostnames, which must
  # resolve to the console and balancerd, while the internal certificates
  # stay self-signed, since a public CA cannot sign their cluster.local names.
  # issuer_ref = {
  #   name = module.letsencrypt_cluster_issuer.issuer_name
  #   kind = "ClusterIssuer"
  # }
  # internal_issuer_ref = {
  #   name = module.self_signed_cluster_issuer.issuer_name
  #   kind = "ClusterIssuer"
  # }
  # console_extra_dns_names   = ["console.mz.example.com"]
  # balancerd_extra_dns_names = ["balancerd.mz.example.com"]

  depends_on = [
    helm_release.materialize_operator,
    module.self_signed_cluster_issuer,
  ]
}
