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

# DSN and secrets live here instead of in the Helm values, which the helm
# provider echoes in plain text in helm_release.metadata on every plan.
# The chart's old Secret (named after the release, e.g. `hydra`) is a Helm hook
# with resource-policy keep, so upgrading leaves it behind; delete it by hand.
resource "kubernetes_secret" "hydra" {
  metadata {
    name      = "${var.release_name}-secrets"
    namespace = local.namespace
  }

  data = local.secret_data

  type = "Opaque"
}

locals {
  namespace = var.create_namespace ? kubernetes_namespace.hydra[0].metadata[0].name : var.namespace

  secrets_system = var.secrets_system != null ? var.secrets_system : random_password.secrets_system[0].result
  secrets_cookie = var.secrets_cookie != null ? var.secrets_cookie : random_password.secrets_cookie[0].result

  # Key names the chart reads when secret.nameOverride points at an existing Secret.
  secret_data = {
    dsn           = var.dsn
    secretsSystem = local.secrets_system
    secretsCookie = local.secrets_cookie
  }

  # The chart only checksums its own Secret, so roll the pods ourselves when ours changes.
  secret_checksum = nonsensitive(sha256(jsonencode(local.secret_data)))

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

  default_helm_values = merge({
    replicaCount = var.replica_count

    secret = {
      enabled      = false
      nameOverride = kubernetes_secret.hydra.metadata[0].name
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

      config = {
        serve = {
          public = {
            port = 4444
          }
          admin = {
            port = 4445
          }
        }

        urls = local.urls_config
      }
    }

    deployment = {
      annotations = {
        "checksum/secrets" = local.secret_checksum
      }

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
      local.tls_deployment_config,
    ),
    local.cors_config,
    local.tls_allow_termination_config,
  )
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
  ]
}
