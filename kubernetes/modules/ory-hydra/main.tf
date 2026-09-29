resource "kubernetes_namespace" "hydra" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
  }
}

resource "random_password" "secrets_system" {
  count   = var.secrets_system == null ? 1 : 0
  length  = 32
  special = false
}

resource "random_password" "secrets_cookie" {
  count   = var.secrets_cookie == null ? 1 : 0
  length  = 32
  special = false
}

locals {
  namespace = var.create_namespace ? kubernetes_namespace.hydra[0].metadata[0].name : var.namespace

  secrets_system = var.secrets_system != null ? var.secrets_system : random_password.secrets_system[0].result
  secrets_cookie = var.secrets_cookie != null ? var.secrets_cookie : random_password.secrets_cookie[0].result

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
  tls_mount_dir = "/etc/hydra/tls"

  # The chart defaults serve.tls.allow_termination_from, which Hydra 26.3.13
  # removed and now rejects at startup. Older versions need it to serve plain
  # HTTP on listeners without a cert, so only null it out from 26.3.13 on.
  image_tag_parts            = try(regex("^v?(\\d+)\\.(\\d+)\\.(\\d+)$", var.image_tag), null)
  drop_tls_allow_termination = local.image_tag_parts == null ? false : (tonumber(local.image_tag_parts[0]) * 1000000 + tonumber(local.image_tag_parts[1]) * 1000 + tonumber(local.image_tag_parts[2])) >= 26003013
  tls_allow_termination_config = local.drop_tls_allow_termination ? {
    hydra = { config = { serve = { tls = { allow_termination_from = null } } } }
  } : {}

  # Configure TLS on the public listener so Hydra serves HTTPS there.
  # The admin listener stays HTTP (internal-only, probes work, selfservice UI and
  # Maester access it within the cluster). `enabled: true` is required — without
  # it Hydra ignores cert/key paths and serves plain HTTP.
  tls_hydra_config = local.tls_enabled ? {
    hydra = {
      config = {
        serve = {
          public = {
            tls = {
              enabled = true
              cert    = { path = "${local.tls_mount_dir}/tls.crt" }
              key     = { path = "${local.tls_mount_dir}/tls.key" }
            }
          }
        }
      }
    }
  } : {}

  cors_config = length(var.cors_allowed_origins) > 0 ? {
    hydra = {
      config = {
        serve = {
          public = {
            cors = {
              enabled           = true
              allowed_origins   = var.cors_allowed_origins
              allowed_methods   = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
              allowed_headers   = var.cors_allowed_headers
              exposed_headers   = ["Content-Type"]
              allow_credentials = true
            }
          }
        }
      }
    }
  } : {}

  # Extra volumes, mounts and env for the Hydra container, built here in one
  # place: the deep merge below replaces lists rather than appending to them,
  # so separate fragments would silently drop each other's entries.
  token_hook_enabled     = nonsensitive(var.token_hook != null)
  token_hook_ca_secret   = local.token_hook_enabled ? nonsensitive(var.token_hook.ca_secret_name) : null
  token_hook_ca_mount    = "/etc/hydra/token-hook-ca"
  token_hook_secret_name = "${var.release_name}-token-hook"

  extra_volumes = concat(
    local.tls_enabled ? [{ name = "tls-cert", secret = { secretName = var.tls_cert_secret_name } }] : [],
    local.token_hook_ca_secret != null ? [{
      name = "token-hook-ca"
      secret = {
        secretName = local.token_hook_ca_secret
        items      = [{ key = "ca.crt", path = "ca.crt" }]
      }
    }] : [],
  )
  extra_volume_mounts = concat(
    local.tls_enabled ? [{ name = "tls-cert", mountPath = local.tls_mount_dir, readOnly = true }] : [],
    local.token_hook_ca_secret != null ? [{ name = "token-hook-ca", mountPath = local.token_hook_ca_mount, readOnly = true }] : [],
  )
  extra_env = concat(
    # The hook's API key reaches Hydra from a Secret, not the config: the
    # chart renders hydra.config into a ConfigMap, which anyone with the
    # built-in "view" role can read.
    local.token_hook_enabled ? [{
      name      = "OAUTH2_TOKEN_HOOK_AUTH_CONFIG_VALUE"
      valueFrom = { secretKeyRef = { name = local.token_hook_secret_name, key = "api-key" } }
    }] : [],
    # Go reads SSL_CERT_DIR in addition to the system bundle file, so this adds
    # the CA that signs the hook's certificate without dropping public roots.
    local.token_hook_ca_secret != null ? [{ name = "SSL_CERT_DIR", value = local.token_hook_ca_mount }] : [],
  )

  # Always emitted: empty lists are the chart's own defaults, and helm_values
  # (merged last) still overrides them.
  deployment_extras_config = {
    deployment = {
      extraVolumes      = local.extra_volumes
      extraVolumeMounts = local.extra_volume_mounts
      extraEnv          = local.extra_env
    }
  }

  urls_config = merge(
    {
      self = {
        issuer = var.issuer_url
      }
    },
    var.login_url != null ? { login = var.login_url } : {},
    var.consent_url != null ? { consent = var.consent_url } : {},
    var.logout_url != null ? { logout = var.logout_url } : {},
  )

  # Hydra calls the token hook on every token issuance; the shared key goes in
  # a header the hook validates. Only emitted when a hook is configured, so the
  # chart keeps its own defaults otherwise. The key itself is not in here: it
  # comes from OAUTH2_TOKEN_HOOK_AUTH_CONFIG_VALUE (see extra_env).
  token_hook_config = local.token_hook_enabled ? {
    token_hook = {
      url = var.token_hook.url
      auth = {
        type = "api_key"
        config = {
          in   = "header"
          name = var.token_hook.api_key_header
        }
      }
    }
  } : {}

  oauth2_config = length(local.token_hook_config) > 0 ? { oauth2 = local.token_hook_config } : {}

  default_helm_values = merge({
    replicaCount = var.replica_count

    secret = {
      enabled = true
    }

    maester = {
      enabled = var.maester_enabled
    }

    # Janitor cleans stale rows the DB has no TTL for. cleanupRequests is the
    # important one: login and consent flow-state tables only get cleared here,
    # so without it they grow unbounded on every engine, Cockroach included.
    janitor = {
      enabled         = var.janitor_enabled
      cleanupGrants   = true
      cleanupRequests = true
      cleanupTokens   = true
    }

    cronjob = {
      janitor = {
        schedule     = var.janitor_schedule
        nodeSelector = var.node_selector
      }
    }

    hydra = {
      automigration = {
        enabled = var.automigration_enabled
        type    = var.automigration_type
      }

      config = merge({
        dsn = var.dsn

        serve = {
          public = {
            port = 4444
          }
          admin = {
            port = 4445
          }
        }

        secrets = {
          system = [local.secrets_system]
          cookie = [local.secrets_cookie]
        }

        urls = local.urls_config
      }, local.oauth2_config)
    }

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
        port    = 4444
      }
      admin = {
        enabled = true
        type    = "ClusterIP"
        port    = 4445
      }
    }
  }, local.image_config, local.image_pull_secrets_config)

  # Deep-merge TLS and CORS config so they merge into the existing hydra.config and deployment blocks.
  default_helm_values_with_tls = provider::deepmerge::mergo(
    provider::deepmerge::mergo(
      provider::deepmerge::mergo(local.default_helm_values, local.tls_hydra_config),
      local.deployment_extras_config,
    ),
    local.cors_config,
    local.tls_allow_termination_config,
  )
}

resource "kubernetes_secret" "token_hook" {
  count = local.token_hook_enabled ? 1 : 0

  metadata {
    name      = local.token_hook_secret_name
    namespace = local.namespace
  }

  data = {
    "api-key" = var.token_hook.api_key
  }
}

resource "helm_release" "hydra" {
  name       = var.release_name
  namespace  = local.namespace
  repository = "https://k8s.ory.sh/helm/charts"
  chart      = "hydra"
  version    = var.chart_version
  timeout    = var.install_timeout

  values = [
    yamlencode(provider::deepmerge::mergo(local.default_helm_values_with_tls, var.helm_values))
  ]

  depends_on = [
    kubernetes_namespace.hydra,
    kubernetes_secret.token_hook,
  ]
}
