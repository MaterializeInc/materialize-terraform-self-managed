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

# The entire provider list — including client secrets — lives in this Secret
# and reaches Kratos as a single JSON-valued environment variable, so the
# Helm-rendered ConfigMap never carries a credential.
resource "kubernetes_secret" "upstream_oidc_providers_env" {
  count = length(var.upstream_oidc_providers) > 0 ? 1 : 0

  metadata {
    name      = "${var.release_name}-upstream-oidc-providers"
    namespace = local.namespace
  }

  data = {
    providers = jsonencode(local.upstream_oidc_provider_objects)
  }

  type = "Opaque"
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

  tls_volumes = local.tls_enabled ? [
    {
      name = "tls-cert"
      secret = {
        secretName = var.tls_cert_secret_name
      }
    },
  ] : []

  tls_volume_mounts = local.tls_enabled ? [
    {
      name      = "tls-cert"
      mountPath = local.tls_mount_dir
      readOnly  = true
    },
  ] : []

  smtp_config = var.smtp_connection_uri != null ? {
    courier = {
      smtp = merge(
        { connection_uri = var.smtp_connection_uri },
        var.smtp_from_address != null ? { from_address = var.smtp_from_address } : {},
        var.smtp_from_name != null ? { from_name = var.smtp_from_name } : {},
      )
    }
  } : {}

  # Standard OIDC claim mapper. Maps the upstream IdP's email claim onto the
  # Kratos identity's email trait. Encoded as a base64:// data URI so Kratos
  # can read it inline, no ConfigMap needed.
  upstream_oidc_mapper_jsonnet = <<-EOT
    local claims = std.extVar('claims');
    local raw = if std.objectHas(claims, 'raw_claims') then claims.raw_claims else {};
    local groups_from(src) = if std.objectHas(src, 'groups') then src.groups else [];
    {
      identity: {
        traits: {
          email: claims.email,
          // Kratos exposes standard OIDC fields (email, sub, aud, ...) flat on
          // claims and everything else under claims.raw_claims. SAML-derived
          // group memberships come in as a non-standard claim, so check both.
          groups: if std.length(groups_from(claims)) > 0 then groups_from(claims) else groups_from(raw),
        },
      },
    }
  EOT

  upstream_oidc_mapper_data_uri = "base64://${base64encode(local.upstream_oidc_mapper_jsonnet)}"

  # The provider objects as Kratos expects them. They only ever land in a
  # Kubernetes Secret, never in the Helm-rendered ConfigMap.
  upstream_oidc_provider_objects = [
    for p in var.upstream_oidc_providers : merge(
      {
        id            = p.id
        provider      = p.provider
        client_id     = p.client_id
        client_secret = p.client_secret
        issuer_url    = p.issuer_url
        scope         = p.scope
        mapper_url    = local.upstream_oidc_mapper_data_uri
      },
      p.label != null ? { label = p.label } : {},
    )
  ]

  # The provider list reaches Kratos as one JSON-valued environment variable;
  # configx decodes JSON env values into arrays and the variable takes
  # precedence over the (provider-less) file configuration. This is the
  # delivery mechanism Ory recommends for keeping provider secrets out of the
  # chart's ConfigMap: https://github.com/ory/k8s/issues/423
  upstream_oidc_extra_env = length(var.upstream_oidc_providers) > 0 ? [
    {
      name = "SELFSERVICE_METHODS_OIDC_CONFIG_PROVIDERS"
      valueFrom = {
        secretKeyRef = {
          name = kubernetes_secret.upstream_oidc_providers_env[0].metadata[0].name
          key  = "providers"
        }
      }
    },
  ] : []

  # Roll the pods when the provider list changes: the chart's checksum
  # annotation only covers the ConfigMap, and environment variables are
  # immutable for running pods. The annotation lands on the pod template, so a
  # changed hash triggers a rolling restart.
  upstream_oidc_env_annotations = length(var.upstream_oidc_providers) > 0 ? {
    "checksum/upstream-oidc-providers" = sha256(jsonencode(local.upstream_oidc_provider_objects))
  } : {}

  deployment_config = length(local.tls_volumes) > 0 || length(local.upstream_oidc_extra_env) > 0 ? {
    deployment = merge(
      length(local.tls_volumes) > 0 ? {
        extraVolumes      = local.tls_volumes
        extraVolumeMounts = local.tls_volume_mounts
      } : {},
      length(local.upstream_oidc_extra_env) > 0 ? { extraEnv = local.upstream_oidc_extra_env } : {},
      length(local.upstream_oidc_env_annotations) > 0 ? { annotations = local.upstream_oidc_env_annotations } : {},
    )
  } : {}

  # The providers themselves are delivered exclusively via the environment
  # variable; enabled-with-no-providers is valid configuration for workloads
  # that never receive it (migration job, courier).
  upstream_oidc_config = length(var.upstream_oidc_providers) > 0 ? {
    kratos = {
      config = {
        selfservice = {
          methods = {
            oidc = {
              enabled = true
            }
          }
        }
      }
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

  # Deep-merge optional features (TLS, upstream OIDC) into the default values.
  default_helm_values_with_extras = provider::deepmerge::mergo(
    provider::deepmerge::mergo(
      provider::deepmerge::mergo(local.default_helm_values, local.tls_kratos_config),
      local.deployment_config,
    ),
    local.upstream_oidc_config,
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
    yamlencode(provider::deepmerge::mergo(local.default_helm_values_with_extras, var.helm_values))
  ]

  depends_on = [
    kubernetes_namespace.kratos,
  ]
}
