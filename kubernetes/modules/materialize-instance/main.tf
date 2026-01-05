locals {
  secret_name    = "${var.instance_name}-materialize-backend"
  mz_resource_id = data.kubernetes_resource.materialize_instance.object.status.resourceId
}
# Set system parameters after instance is ready using a Kubernetes Job
#https://materialize.com/changelog/2024-02-08-default-configuration-parameters/
resource "kubernetes_job" "system_parameters" {
  metadata {
    name      = "${var.instance_name}-set-system-params"
    namespace = var.instance_namespace
  }

  spec {
    ttl_seconds_after_finished = 300
    backoff_limit              = 3

    template {
      metadata {
        labels = {
          app = "${var.instance_name}-set-system-params"
        }
      }

      spec {
        restart_policy = "Never"

        container {
          name  = "psql"
          image = "postgres:16-alpine"

          command = [
            "sh", "-c",
            "PGPASSWORD=$MZ_PASSWORD psql -h $MZ_HOST -p 6875 -U mz_system -d materialize -c \"ALTER SYSTEM SET cluster TO 'quickstart';\""
          ]

          env {
            name  = "MZ_HOST"
            value = "mz${local.mz_resource_id}-balancerd.${var.instance_namespace}.svc.cluster.local"
          }

          env {
            name = "MZ_PASSWORD"
            value_from {
              secret_key_ref {
                name = local.secret_name
                key  = "external_login_password_mz_system"
              }
            }
          }
        }
      }
    }
  }

  wait_for_completion = true

  timeouts {
    create = "5m"
  }

  depends_on = [
    kubectl_manifest.materialize_instance
  ]
}

# Create a namespace for this Materialize instance
resource "kubernetes_namespace" "instance" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.instance_namespace
  }
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
    spec = {
      environmentdImageRef      = "materialize/environmentd:${var.environmentd_version}"
      backendSecretName         = local.secret_name
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
    name      = local.secret_name
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
