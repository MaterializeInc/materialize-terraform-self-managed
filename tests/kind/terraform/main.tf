# Test deployment of Materialize on kind
# This uses the actual Terraform modules to validate they work correctly

# Install cert-manager for TLS certificates
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.16.2"

  set {
    name  = "crds.enabled"
    value = "true"
  }

  wait = true
}

# Create a self-signed cluster issuer for TLS
module "self_signed_cluster_issuer" {
  source = "../../../kubernetes/modules/self-signed-cluster-issuer"

  name_prefix = "mz-test"

  depends_on = [helm_release.cert_manager]
}

# Install the Materialize operator using the base operator module
module "operator" {
  source = "../../../kubernetes/modules/operator"

  name_prefix      = "materialize-operator"
  operator_version = var.operator_version

  # Pass helm values directly - the generated types are validated by fixture tests
  helm_values = {
    observability = {
      podMetrics = {
        enabled = true
      }
    }
  }

  # For kind, use insecure TLS verification for metrics server
  metrics_server_values = {
    metrics_enabled       = "true"
    skip_tls_verification = true
  }

  depends_on = [helm_release.cert_manager]
}

# Create the Materialize instance using the materialize-instance module
module "materialize_instance" {
  source = "../../../kubernetes/modules/materialize-instance"

  instance_name                     = "test-instance"
  instance_namespace                = "materialize-environment"
  create_namespace                  = true
  external_login_password_mz_system = "test"

  # Backend URLs pointing to our test PostgreSQL and MinIO
  metadata_backend_url = "postgres://materialize:materialize@postgres.postgres.svc.cluster.local:5432/materialize?sslmode=disable"
  persist_backend_url  = "s3://minioadmin:minioadmin@materialize/test?endpoint=http%3A%2F%2Fminio.minio.svc.cluster.local%3A9000&region=minio"

  # License key for testing (set via TF_VAR_license_key)
  license_key = var.license_key != "" ? var.license_key : null

  # Use the self-signed issuer for TLS
  issuer_ref = {
    name = module.self_signed_cluster_issuer.issuer_name
    kind = "ClusterIssuer"
  }

  # Pass empty override - the generated types are validated by fixture tests
  materialize_spec_override = {}

  depends_on = [
    module.operator,
    module.self_signed_cluster_issuer,
  ]
}
