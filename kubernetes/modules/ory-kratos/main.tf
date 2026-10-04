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

# Provider list (with client secrets) reaches Kratos as a JSON env var from this
# Secret, so the Helm-rendered ConfigMap never carries a credential.
resource "kubernetes_secret" "upstream_oidc_providers_env" {
  count = length(var.upstream_identity_providers) > 0 ? 1 : 0

  metadata {
    name      = "${var.release_name}-upstream-oidc-providers"
    namespace = local.namespace
  }

  data = {
    providers = jsonencode(local.upstream_oidc_provider_objects)
  }

  type = "Opaque"
}

# Same for the SAML (jackson/Polis) providers, including the raw IdP metadata.
resource "kubernetes_secret" "saml_providers_env" {
  count = length(var.saml_providers) > 0 ? 1 : 0

  metadata {
    name      = "${var.release_name}-saml-providers"
    namespace = local.namespace
  }

  data = {
    providers = jsonencode(local.saml_provider_objects)
  }

  type = "Opaque"
}

# Not in the Helm values, which the helm provider shows in plain text on every
# plan. The chart's own Secret (named after the release) is a keep-policy hook,
# so upgrading leaves it behind; delete it by hand.
resource "kubernetes_secret" "kratos" {
  metadata {
    name      = "${var.release_name}-secrets"
    namespace = local.namespace
  }

  data = local.secret_data

  type = "Opaque"
}

locals {
  namespace = var.create_namespace ? kubernetes_namespace.kratos[0].metadata[0].name : var.namespace

  secrets_default = var.secrets_default != null ? var.secrets_default : random_password.secrets_default[0].result
  secrets_cookie  = var.secrets_cookie != null ? var.secrets_cookie : random_password.secrets_cookie[0].result
  secrets_cipher  = var.secrets_cipher != null ? var.secrets_cipher : random_password.secrets_cipher[0].result

  smtp_enabled = var.smtp_connection_uri != null

  # Key names the chart reads when secret.nameOverride points at an existing Secret.
  secret_data = merge(
    {
      dsn            = var.dsn
      secretsDefault = local.secrets_default
      secretsCookie  = local.secrets_cookie
      secretsCipher  = local.secrets_cipher
    },
    local.smtp_enabled ? { smtpConnectionURI = var.smtp_connection_uri } : {},
  )

  # The chart only checksums its own Secret, so roll the pods ourselves when ours changes.
  secret_checksum = nonsensitive(sha256(jsonencode(local.secret_data)))

  # The chart only wires smtpConnectionURI when connection_uri is in the values,
  # so inject it here. The courier StatefulSet inherits deployment.extraEnv.
  smtp_extra_env = local.smtp_enabled ? [
    {
      name = "COURIER_SMTP_CONNECTION_URI"
      valueFrom = {
        secretKeyRef = {
          name = kubernetes_secret.kratos.metadata[0].name
          key  = "smtpConnectionURI"
        }
      }
    },
  ] : []

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

  # Kratos enables TLS whenever cert/key paths are set (no `enabled` field).
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

  smtp_config = local.smtp_enabled && (var.smtp_from_address != null || var.smtp_from_name != null) ? {
    courier = {
      smtp = merge(
        var.smtp_from_address != null ? { from_address = var.smtp_from_address } : {},
        var.smtp_from_name != null ? { from_name = var.smtp_from_name } : {},
      )
    }
  } : {}

  # Maps the upstream email and groups claims onto identity traits. Shared by
  # the OIDC and SAML methods; passed inline as a base64:// data URI.
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

  upstream_oidc_provider_objects = [
    for p in var.upstream_identity_providers : merge(
      {
        id            = p.id
        provider      = p.provider
        client_id     = p.client_id
        client_secret = p.client_secret
        issuer_url    = p.issuer_url
        scope         = p.scope
        mapper_url    = local.upstream_oidc_mapper_data_uri
        # Same as the SAML providers: refresh traits (groups) on every login.
        update_identity_on_login = "automatic"
      },
      p.label != null ? { label = p.label } : {},
    )
  ]

  # configx decodes the JSON env value into an array that overrides the
  # provider-less file config. Ory's recommended way to keep provider secrets
  # out of the ConfigMap: https://github.com/ory/k8s/issues/423
  upstream_oidc_extra_env = length(var.upstream_identity_providers) > 0 ? [
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

  # The chart's checksum only covers the ConfigMap, so roll the pods ourselves
  # when the provider list changes.
  upstream_oidc_env_annotations = length(var.upstream_identity_providers) > 0 ? {
    "checksum/upstream-oidc-providers" = sha256(jsonencode(local.upstream_oidc_provider_objects))
  } : {}

  extra_env = concat(local.upstream_oidc_extra_env, local.saml_extra_env, local.smtp_extra_env)

  deployment_config = {
    deployment = merge(
      # One attribute per conditional: a two-attribute object and {} fail with
      # "Inconsistent conditional result types" once TLS is enabled.
      length(local.tls_volumes) > 0 ? { extraVolumes = local.tls_volumes } : {},
      length(local.tls_volumes) > 0 ? { extraVolumeMounts = local.tls_volume_mounts } : {},
      length(local.extra_env) > 0 ? { extraEnv = local.extra_env } : {},
      { annotations = merge({ "checksum/secrets" = local.secret_checksum }, local.upstream_oidc_env_annotations, local.saml_env_annotations) },
    )
  }

  # Providers come only from the env var; enabled with no providers is valid
  # for workloads that never get it (migration job, courier).
  upstream_oidc_config = length(var.upstream_identity_providers) > 0 ? {
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

  saml_provider_objects = [
    for p in var.saml_providers : merge(
      {
        id                   = p.id
        provider             = "jackson"
        client_id            = p.client_id
        client_secret        = p.client_secret
        issuer_url           = p.issuer_url
        auth_url             = p.auth_url
        token_url            = p.token_url
        raw_idp_metadata_xml = "base64://${base64encode(p.raw_idp_metadata_xml)}"
        mapper_url           = local.upstream_oidc_mapper_data_uri
        # Re-run the mapper on every login, not just registration, so a group
        # removed in the IdP drops the matching Materialize role at next sign-in.
        update_identity_on_login = "automatic"
      },
      p.label != null ? { label = p.label } : {},
    )
  ]

  saml_extra_env = length(var.saml_providers) > 0 ? [
    {
      name = "SELFSERVICE_METHODS_SAML_CONFIG_PROVIDERS"
      valueFrom = {
        secretKeyRef = {
          name = kubernetes_secret.saml_providers_env[0].metadata[0].name
          key  = "providers"
        }
      }
    },
  ] : []

  saml_env_annotations = length(var.saml_providers) > 0 ? {
    "checksum/saml-providers" = sha256(jsonencode(local.saml_provider_objects))
  } : {}

  # Providers come only from the env var.
  saml_config = length(var.saml_providers) > 0 ? {
    kratos = {
      config = {
        selfservice = {
          methods = {
            saml = {
              enabled = true
              config = {
                base_redirect_uri = var.saml_base_redirect_uri
              }
            }
          }
        }
      }
    }
  } : {}

  default_helm_values = merge({
    replicaCount = var.replica_count

    # Scrapes the admin listener over plain HTTP. The chart renders it only if
    # the monitoring.coreos.com API already exists.
    serviceMonitor = {
      enabled = var.enable_service_monitor
    }

    secret = {
      enabled      = false
      nameOverride = kubernetes_secret.kratos.metadata[0].name
    }

    kratos = merge(
      {
        automigration = {
          enabled = var.automigration_enabled
          type    = var.automigration_type
        }

        config = merge(
          {
            serve = {
              public = {
                port = 4433
              }
              admin = {
                port = 4434
              }
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

  default_helm_values_with_extras = provider::deepmerge::mergo(
    provider::deepmerge::mergo(
      provider::deepmerge::mergo(
        provider::deepmerge::mergo(local.default_helm_values, local.tls_kratos_config),
        local.deployment_config,
      ),
      local.upstream_oidc_config,
    ),
    local.saml_config,
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
