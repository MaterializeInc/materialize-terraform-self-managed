locals {
  secret_name      = "${var.instance_name}-materialize-backend"
  mz_resource_id   = data.kubernetes_resource.materialize_instance.object.status.resourceId
  create_superuser = contains(["Password", "Sasl"], var.authenticator_kind) && var.superuser_credentials != null

  use_provided_password = trimspace(try(var.superuser_credentials.password, "")) != ""
  superuser_password    = local.create_superuser ? (local.use_provided_password ? var.superuser_credentials.password : random_password.superuser_password[0].result) : ""
}

check "superuser_credentials_warning" {
  assert {
    condition     = !(var.superuser_credentials != null && var.authenticator_kind == "None")
    error_message = "Warning: superuser_credentials is set but authenticator_kind is 'None'. Superuser will not be created. Set authenticator_kind to 'Password' or 'Sasl' for superuser creation to take effect."
  }
}

resource "random_password" "superuser_password" {
  count            = local.create_superuser ? 1 : 0
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Secret to store superuser credentials (avoids exposing password in pod spec)
resource "kubernetes_secret" "superuser_credentials" {
  count = local.create_superuser ? 1 : 0

  metadata {
    name      = "${var.instance_name}-superuser-credentials"
    namespace = var.instance_namespace
  }

  data = {
    username = var.superuser_credentials.username
    password = local.superuser_password
  }

}

# Create a job to create the user with superuser privileges
# https://materialize.com/docs/security/self-managed/access-control/manage-roles/#create-individual-userservice-account-roles
resource "kubernetes_job" "create_superuser" {
  count = local.create_superuser ? 1 : 0
  metadata {
    generate_name = "${var.instance_name}-create-superuser-"
    namespace     = var.instance_namespace
  }

  spec {
    ttl_seconds_after_finished = 600
    backoff_limit              = 3

    template {
      metadata {
        labels = {
          app = "${var.instance_name}-create-role"
        }
      }

      spec {
        restart_policy = "Never"

        container {
          name  = "psql"
          image = "postgres:18-alpine"

          command = [
            "sh", "-c",
            <<-EOT
            ROLE_EXISTS=$(PGPASSWORD=$MZ_PASSWORD psql -h $MZ_HOST -p 6875 -U mz_system -d materialize -tAc "SELECT 1 FROM mz_roles WHERE name = '$SUPERUSER_USERNAME';")
            if [ -z "$ROLE_EXISTS" ]; then
              PGPASSWORD=$MZ_PASSWORD psql -h $MZ_HOST -p 6875 -U mz_system -d materialize \
                -c "CREATE ROLE $SUPERUSER_USERNAME WITH SUPERUSER LOGIN PASSWORD '$SUPERUSER_PASSWORD';"
            else
              PGPASSWORD=$MZ_PASSWORD psql -h $MZ_HOST -p 6875 -U mz_system -d materialize \
                -c "ALTER ROLE $SUPERUSER_USERNAME PASSWORD '$SUPERUSER_PASSWORD';"
            fi
            EOT
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

          env {
            name = "SUPERUSER_USERNAME"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.superuser_credentials[0].metadata[0].name
                key  = "username"
              }
            }
          }

          env {
            name = "SUPERUSER_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.superuser_credentials[0].metadata[0].name
                key  = "password"
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
    update = "5m"
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
