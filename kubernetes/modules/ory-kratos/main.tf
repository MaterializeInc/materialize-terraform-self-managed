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

# The SAML (jackson/Polis) provider list — including client secrets and the raw
# IdP metadata — reaches Kratos as a single JSON-valued environment variable, so
# the Helm-rendered ConfigMap never carries a credential.
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

# DSN, secrets and the SMTP URI live here instead of in the Helm values, which
# the helm provider echoes in plain text in helm_release.metadata on every plan.
# The chart's old Secret (named after the release, e.g. `kratos`) is a Helm hook
# with resource-policy keep, so upgrading leaves it behind; delete it by hand.
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

  smtp_config = local.smtp_enabled && (var.smtp_from_address != null || var.smtp_from_name != null) ? {
    courier = {
      smtp = merge(
        var.smtp_from_address != null ? { from_address = var.smtp_from_address } : {},
        var.smtp_from_name != null ? { from_name = var.smtp_from_name } : {},
      )
    }
  } : {}

  # Claim mapper template. Each provider gets its own copy with its settings
  # filled in at __MAPPER_CONFIG__, so a provider can only sign in its own
  # email domains and grant the groups it is allowed to. Email goes to traits
  # and metadata_public, groups to metadata_public only. Users cannot write
  # metadata_public through any self-service flow, so what Materialize trusts
  # only ever comes from here.
  claim_mapper_template = <<-EOT
    local cfg = __MAPPER_CONFIG__;
    local claims = std.extVar('claims');
    // Kratos exposes standard OIDC fields (email, email_verified, ...) flat on
    // claims and everything else under raw_claims, so groups come from there.
    local raw = if std.objectHas(claims, 'raw_claims') && std.isObject(claims.raw_claims) then claims.raw_claims else {};
    local is_true(v) = v == true || v == 'true';
    local email_verified =
      (std.objectHas(claims, 'email_verified') && is_true(claims.email_verified)) ||
      (std.objectHas(raw, 'email_verified') && is_true(raw.email_verified));
    local email = std.asciiLower(if std.objectHas(claims, 'email') && std.isString(claims.email) then claims.email else '');
    local email_parts = std.split(email, '@');
    local email_domain = if std.length(email_parts) == 2 && email_parts[0] != '' then email_parts[1] else '';
    local groups_claim =
      if std.objectHas(claims, 'groups') then claims.groups
      else if std.objectHas(raw, 'groups') then raw.groups
      else [];
    local groups = std.set([
      g
      for g in (if std.isArray(groups_claim) then groups_claim else [])
      if std.isString(g) &&
         (cfg.allowed_groups == null || std.member(cfg.allowed_groups, g)) &&
         (cfg.group_prefix == null || std.startsWith(g, cfg.group_prefix))
    ]);
    {
      assert email_domain != '' : 'The identity provider did not send a valid email address.',
      assert std.member(cfg.allowed_email_domains, email_domain) : 'This email domain may not sign in through this identity provider.',
      assert !cfg.require_email_verified || email_verified : 'The identity provider did not mark this email address as verified.',
      identity: {
        traits: {
          email: email,
        },
        // During SSO registration Kratos keeps traits the user submits over
        // these, so Materialize reads email and groups from metadata_public.
        metadata_public: {
          email: email,
          groups: groups,
        },
      },
    }
  EOT

  # The provider objects as Kratos expects them. They only ever land in a
  # Kubernetes Secret, never in the Helm-rendered ConfigMap.
  upstream_oidc_provider_objects = [
    for p in var.upstream_identity_providers : merge(
      {
        id            = p.id
        provider      = p.provider
        client_id     = p.client_id
        client_secret = p.client_secret
        issuer_url    = p.issuer_url
        scope         = p.scope
        # Inline as a base64:// data URI, so Kratos needs no ConfigMap.
        mapper_url = "base64://${base64encode(replace(local.claim_mapper_template, "__MAPPER_CONFIG__", jsonencode({
          allowed_email_domains  = [for d in p.allowed_email_domains : lower(d)]
          allowed_groups         = p.allowed_groups
          group_prefix           = p.group_prefix
          require_email_verified = p.require_email_verified
        })))}"
        # Same as the SAML providers: refresh traits and groups on every login.
        update_identity_on_login = "automatic"
      },
      p.label != null ? { label = p.label } : {},
    )
  ]

  # The provider list reaches Kratos as one JSON-valued environment variable;
  # configx decodes JSON env values into arrays and the variable takes
  # precedence over the (provider-less) file configuration. This is the
  # delivery mechanism Ory recommends for keeping provider secrets out of the
  # chart's ConfigMap: https://github.com/ory/k8s/issues/423
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

  # Roll the pods when the provider list changes: the chart's checksum
  # annotation only covers the ConfigMap, and environment variables are
  # immutable for running pods. The annotation lands on the pod template, so a
  # changed hash triggers a rolling restart.
  upstream_oidc_env_annotations = length(var.upstream_identity_providers) > 0 ? {
    "checksum/upstream-oidc-providers" = sha256(jsonencode(local.upstream_oidc_provider_objects))
  } : {}

  extra_env = concat(local.upstream_oidc_extra_env, local.saml_extra_env, local.smtp_extra_env)

  deployment_config = {
    deployment = merge(
      # One attribute per conditional: a multi-attribute object and {} cannot
      # unify as a map when the attribute types differ, so a two-attribute
      # branch fails with "Inconsistent conditional result types" as soon as
      # TLS is enabled.
      length(local.tls_volumes) > 0 ? { extraVolumes = local.tls_volumes } : {},
      length(local.tls_volumes) > 0 ? { extraVolumeMounts = local.tls_volume_mounts } : {},
      length(local.extra_env) > 0 ? { extraEnv = local.extra_env } : {},
      { annotations = merge({ "checksum/secrets" = local.secret_checksum }, local.upstream_oidc_env_annotations, local.saml_env_annotations) },
    )
  }

  # The providers themselves are delivered exclusively via the environment
  # variable; enabled-with-no-providers is valid configuration for workloads
  # that never receive it (migration job, courier).
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

  # The SAML provider objects as Kratos's jackson (Polis) method expects them.
  # They only ever land in a Kubernetes Secret, never in the Helm-rendered
  # ConfigMap. The IdP metadata is delivered inline as a base64:// data URI.
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
        mapper_url = "base64://${base64encode(replace(local.claim_mapper_template, "__MAPPER_CONFIG__", jsonencode({
          allowed_email_domains  = [for d in p.allowed_email_domains : lower(d)]
          allowed_groups         = p.allowed_groups
          group_prefix           = p.group_prefix
          require_email_verified = p.require_email_verified
        })))}"
        # Re-run the mapper on every login, not just registration, so a group
        # removed in the IdP drops the matching Materialize role at next sign-in.
        update_identity_on_login = "automatic"
      },
      p.label != null ? { label = p.label } : {},
    )
  ]

  # Delivered the same way as the OIDC providers: one JSON-valued environment
  # variable that configx decodes into an array and that takes precedence over
  # the provider-less file configuration.
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

  # Roll the pods when the SAML provider list changes, for the same reason as
  # the OIDC checksum: env vars are immutable for running pods.
  saml_env_annotations = length(var.saml_providers) > 0 ? {
    "checksum/saml-providers" = sha256(jsonencode(local.saml_provider_objects))
  } : {}

  # base_redirect_uri is the only file-level SAML config; the providers
  # themselves arrive exclusively via the environment variable.
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

    # Scrapes the admin listener's /admin/metrics/prometheus over plain HTTP.
    # The chart renders the monitor only when the monitoring.coreos.com API
    # already exists.
    serviceMonitor = {
      enabled     = var.enable_service_monitor
      relabelings = var.service_monitor_relabelings
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

    # Deletes rows that expired over keepLast ago, at most batchSize per table
    # per run.
    cleanup = {
      enabled   = var.cleanup_enabled
      batchSize = 1000
      keepLast  = "6h"
    }

    cronjob = {
      cleanup = {
        schedule     = var.cleanup_schedule
        nodeSelector = var.node_selector
        tolerations = [
          for t in var.tolerations : {
            key      = t.key
            operator = t.operator
            value    = t.value
            effect   = t.effect
          }
        ]
        # It only talks to the database.
        automountServiceAccountToken = false
        resources = {
          requests = { cpu = "50m", memory = "64Mi" }
          limits   = { memory = "128Mi" }
        }
      }
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

  # Deep-merge optional features (TLS, upstream OIDC, SAML) into the default
  # values.
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
