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
      enabled = true
    }

    maester = {
      enabled = var.maester_enabled
    }

    hydra = {
      automigration = {
        enabled = var.automigration_enabled
        type    = var.automigration_type
      }

      config = {
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
      }
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
}

resource "helm_release" "hydra" {
  name       = var.release_name
  namespace  = local.namespace
  repository = "https://k8s.ory.sh/helm/charts"
  chart      = "hydra"
  version    = var.chart_version
  timeout    = var.install_timeout

  values = [
    yamlencode(provider::deepmerge::mergo(local.default_helm_values, var.helm_values))
  ]

  depends_on = [
    kubernetes_namespace.hydra,
  ]
}
