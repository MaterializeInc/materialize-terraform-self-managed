resource "kubernetes_namespace" "kratos" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
  }
}

resource "random_password" "secrets_default" {
  count   = var.secrets_default == null ? 1 : 0
  length  = 32
  special = false
}

resource "random_password" "secrets_cookie" {
  count   = var.secrets_cookie == null ? 1 : 0
  length  = 32
  special = false
}

resource "random_password" "secrets_cipher" {
  count   = var.secrets_cipher == null ? 1 : 0
  length  = 32
  special = false
}

locals {
  namespace = var.create_namespace ? kubernetes_namespace.kratos[0].metadata[0].name : var.namespace

  secrets_default = var.secrets_default != null ? var.secrets_default : random_password.secrets_default[0].result
  secrets_cookie  = var.secrets_cookie != null ? var.secrets_cookie : random_password.secrets_cookie[0].result
  secrets_cipher  = var.secrets_cipher != null ? var.secrets_cipher : random_password.secrets_cipher[0].result

  identity_schemas_config = length(var.identity_schemas) > 0 ? {
    identitySchemas = var.identity_schemas
  } : {}

  image_config = var.image_repository != null || var.image_tag != null ? {
    image = merge(
      var.image_repository != null ? { repository = var.image_repository } : {},
      var.image_tag != null ? { tag = var.image_tag } : {},
    )
  } : {}

  image_pull_secrets_config = length(var.image_pull_secrets) > 0 ? {
    imagePullSecrets = [for name in var.image_pull_secrets : { name = name }]
  } : {}

  tls_enabled   = var.tls_cert_secret_name != null
  tls_mount_dir = "/etc/kratos/tls"

  # Configure TLS on the public listener so Kratos serves HTTPS. Kratos enables
  # TLS whenever cert/key paths are set — unlike Hydra, there's no `enabled` field.
  tls_kratos_config = local.tls_enabled ? {
    kratos = {
      config = {
        serve = {
          public = {
            tls = {
              cert = { path = "${local.tls_mount_dir}/tls.crt" }
              key  = { path = "${local.tls_mount_dir}/tls.key" }
            }
          }
        }
      }
    }
  } : {}

  tls_deployment_config = local.tls_enabled ? {
    deployment = {
      extraVolumes = [
        {
          name = "tls-cert"
          secret = {
            secretName = var.tls_cert_secret_name
          }
        },
      ]
      extraVolumeMounts = [
        {
          name      = "tls-cert"
          mountPath = local.tls_mount_dir
          readOnly  = true
        },
      ]
    }
  } : {}

  smtp_config = var.smtp_connection_uri != null ? {
    courier = {
      smtp = merge(
        { connection_uri = var.smtp_connection_uri },
        var.smtp_from_address != null ? { from_address = var.smtp_from_address } : {},
        var.smtp_from_name != null ? { from_name = var.smtp_from_name } : {},
      )
    }
  } : {}

  default_helm_values = merge({
    replicaCount = var.replica_count

    secret = {
      enabled = true
    }

    kratos = merge(
      {
        automigration = {
          enabled = var.automigration_enabled
          type    = var.automigration_type
        }

        config = merge(
          {
            dsn = var.dsn

            serve = {
              public = {
                port = 4433
              }
              admin = {
                port = 4434
              }
            }

            secrets = {
              default = [local.secrets_default]
              cookie  = [local.secrets_cookie]
              cipher  = [local.secrets_cipher]
            }

            identity = {
              default_schema_id = var.default_identity_schema_id
            }
          },
          local.smtp_config,
        )
      },
      local.identity_schemas_config,
    )

    deployment = {
      resources = {
        requests = {
          cpu    = var.resources.requests.cpu
          memory = var.resources.requests.memory
        }
        limits = merge(
          { memory = var.resources.limits.memory },
          var.resources.limits.cpu != null ? { cpu = var.resources.limits.cpu } : {}
        )
      }

      nodeSelector = var.node_selector
      tolerations = [
        for t in var.tolerations : {
          key      = t.key
          operator = t.operator
          value    = t.value
          effect   = t.effect
        }
      ]
    }

    pdb = {
      enabled = var.pdb_enabled
      spec = var.pdb_enabled ? {
        minAvailable = var.pdb_min_available
      } : {}
    }

    service = {
      public = {
        enabled = true
        type    = "ClusterIP"
        port    = 4433
      }
      admin = {
        enabled = true
        type    = "ClusterIP"
        port    = 4434
      }
    }
  }, local.image_config, local.image_pull_secrets_config)

  # Deep-merge TLS config into hydra.config and deployment blocks.
  default_helm_values_with_tls = provider::deepmerge::mergo(
    provider::deepmerge::mergo(local.default_helm_values, local.tls_kratos_config),
    local.tls_deployment_config,
  )
}

resource "helm_release" "kratos" {
  name       = var.release_name
  namespace  = local.namespace
  repository = "https://k8s.ory.sh/helm/charts"
  chart      = "kratos"
  version    = var.chart_version
  timeout    = var.install_timeout

  values = [
    yamlencode(provider::deepmerge::mergo(local.default_helm_values_with_tls, var.helm_values))
  ]

  depends_on = [
    kubernetes_namespace.kratos,
  ]
}
