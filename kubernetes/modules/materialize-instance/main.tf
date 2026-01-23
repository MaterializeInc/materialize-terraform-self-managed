# Create a namespace for this Materialize instance
resource "kubernetes_namespace" "instance" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.instance_namespace
  }
}

locals {
  # Build the default spec from explicit variables
  default_spec = {
    environmentdImageRef      = "materialize/environmentd:${var.environmentd_version}"
    backendSecretName         = "${var.instance_name}-materialize-backend"
    authenticatorKind         = var.authenticator_kind
    serviceAccountAnnotations = var.service_account_annotations
    podLabels                 = var.pod_labels
    rolloutStrategy           = var.rollout_strategy
    requestRollout            = var.request_rollout
    forceRollout              = var.force_rollout

    environmentdExtraEnv = length(var.environmentd_extra_env) > 0 ? [{
      name = "MZ_SYSTEM_PARAMETER_DEFAULT"
      value = join(";", [
        for item in var.environmentd_extra_env :
        "${item.name}=${item.value}"
      ])
    }] : null

    environmentdExtraArgs = length(var.environmentd_extra_args) > 0 ? var.environmentd_extra_args : null

    environmentdResourceRequirements = {
      limits = {
        memory = var.memory_limit
      }
      requests = {
        cpu    = var.cpu_request
        memory = var.memory_request
      }
    }
    balancerdResourceRequirements = {
      limits = {
        memory = var.balancer_memory_limit
      }
      requests = {
        cpu    = var.balancer_cpu_request
        memory = var.balancer_memory_request
      }
    }

    balancerdExternalCertificateSpec = var.issuer_ref == null ? null : {
      dnsNames = [
        "balancerd",
      ]
      issuerRef = var.issuer_ref
    }
    consoleExternalCertificateSpec = var.issuer_ref == null ? null : {
      dnsNames = [
        "console",
      ]
      issuerRef = var.issuer_ref
    }
    internalCertificateSpec = var.issuer_ref == null ? null : {
      issuerRef = var.issuer_ref
    }
  }

  # Strip null values from override to avoid overwriting defaults with null
  clean_spec_override = {
    for k, v in var.materialize_spec_override : k => v if v != null
  }

  # Deep merge the default spec with user overrides
  merged_spec = provider::deepmerge::mergo(local.default_spec, local.clean_spec_override)
}

# Create the Materialize instance using the kubernetes_manifest resource
resource "kubectl_manifest" "materialize_instance" {
  field_manager   = "terraform"
  force_conflicts = true

  yaml_body = jsonencode({
    apiVersion = "materialize.cloud/v1alpha1"
    kind       = "Materialize"
    metadata = {
      name      = var.instance_name
      namespace = var.instance_namespace
    }
    spec = local.merged_spec
  })

  wait_for {
    field {
      key        = "status.resourceId"
      value      = ".*"
      value_type = "regex"
    }
  }

  depends_on = [
    kubernetes_secret.materialize_backend,
    kubernetes_namespace.instance,
  ]
}

# Create a secret with connection information for the Materialize instance
resource "kubernetes_secret" "materialize_backend" {
  metadata {
    name      = "${var.instance_name}-materialize-backend"
    namespace = var.instance_namespace
  }

  data = merge(
    {
      metadata_backend_url = var.metadata_backend_url
      persist_backend_url  = var.persist_backend_url
      license_key          = var.license_key == null ? "" : var.license_key
    },
    contains(["Password", "Sasl"], var.authenticator_kind) && var.external_login_password_mz_system != null ? {
      external_login_password_mz_system = var.external_login_password_mz_system
    } : {}
  )

  depends_on = [
    kubernetes_namespace.instance
  ]
}

# Retrieve the resource ID of the Materialize instance
data "kubernetes_resource" "materialize_instance" {
  api_version = "materialize.cloud/v1alpha1"
  kind        = "Materialize"
  metadata {
    name      = var.instance_name
    namespace = var.instance_namespace
  }

  depends_on = [
    kubectl_manifest.materialize_instance
  ]
}
