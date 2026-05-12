resource "kubernetes_namespace" "polis" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
  }
}

resource "random_password" "admin_api_keys" {
  count   = var.admin_api_keys == null ? 1 : 0
  length  = 32
  special = false
}

resource "random_password" "nextauth_secret" {
  count   = var.nextauth_secret == null ? 1 : 0
  length  = 32
  special = false
}

resource "random_password" "db_encryption_key" {
  count   = var.db_encryption_key == null ? 1 : 0
  length  = 32
  special = false
}

locals {
  namespace = var.create_namespace ? kubernetes_namespace.polis[0].metadata[0].name : var.namespace

  admin_api_keys    = var.admin_api_keys != null ? var.admin_api_keys : random_password.admin_api_keys[0].result
  nextauth_secret   = var.nextauth_secret != null ? var.nextauth_secret : random_password.nextauth_secret[0].result
  db_encryption_key = var.db_encryption_key != null ? var.db_encryption_key : random_password.db_encryption_key[0].result

  secret_name = "${var.release_name}-config"

  image_config = {
    image = merge(
      { pullPolicy = var.image_pull_policy },
      var.image_registry != null ? { registry = var.image_registry } : {},
      var.image_repository != null ? { repository = var.image_repository } : {},
      var.image_tag != null ? { tag = var.image_tag } : {},
    )
  }

  image_pull_secrets_config = length(var.image_pull_secrets) > 0 ? {
    imagePullSecrets = [for name in var.image_pull_secrets : { name = name }]
  } : {}

  # Polis only honors SAML_AUDIENCE when set as an env var; the chart does not
  # plumb it through values, so route it through deployment.extraEnvs.
  saml_audience_env = var.saml_audience != null ? [{
    name  = "SAML_AUDIENCE"
    value = var.saml_audience
  }] : []

  extra_envs = concat(
    local.saml_audience_env,
    [for k, v in var.extra_env : { name = k, value = v }],
  )

  # The chart's default OTLP endpoints assume a kube-prometheus-stack install
  # in an 'observability' namespace. Most clusters don't have it, and the
  # OTel SDK keeps logging connection errors. Blank them when disabled.
  monitoring_config = var.monitoring_enabled ? {} : {
    monitoring = {
      enableDebug = "false"
      metrics = {
        otlpEndpoint = ""
        otlpProtocol = "http/protobuf"
      }
      traces = {
        otlpEndpoint = ""
        otlpProtocol = "http/protobuf"
        redact       = { enabled = true }
      }
    }
  }

  default_helm_values = merge({
    fullnameOverride = var.release_name
    replicaCount     = var.replica_count

    dbType = "postgres"
    dbSSL  = var.db_ssl

    # Use our own secret instead of the chart's (which hardcodes a cockroach DSN).
    secret = {
      enabled      = false
      nameOverride = kubernetes_secret.polis.metadata[0].name
    }

    polis = {
      hosted            = var.hosted
      idpEnabled        = var.idp_enabled
      dbManualMigration = false
      dbEncryptionKey   = local.db_encryption_key
      nextAuthUrl       = var.external_url
      nextAuthAcl       = var.nextauth_acl
    }

    service = {
      port = var.port
      type = "ClusterIP"
    }

    deployment = {
      extraEnvs    = local.extra_envs
      nodeSelector = var.node_selector
      tolerations = [for t in var.tolerations : {
        key      = t.key
        operator = t.operator
        value    = t.value
        effect   = t.effect
      }]
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
    }
  }, local.image_config, local.image_pull_secrets_config, local.monitoring_config)

  merged_helm_values = provider::deepmerge::mergo(local.default_helm_values, var.helm_values)
}

# Secret feeding the chart's envFrom. The chart's built-in secret template
# hardcodes a CockroachDB DSN, so we always disable it and provide our own
# with the Postgres DB_URL plus the auth secrets the container expects.
resource "kubernetes_secret" "polis" {
  metadata {
    name      = local.secret_name
    namespace = local.namespace
  }

  data = {
    DB_URL          = var.dsn
    API_KEYS        = local.admin_api_keys
    NEXTAUTH_SECRET = local.nextauth_secret
  }
}

resource "helm_release" "polis" {
  name      = var.release_name
  namespace = local.namespace
  chart     = "oci://${var.chart_registry}/${var.chart_repository}"
  version   = var.chart_version
  timeout   = var.install_timeout

  repository_username = var.oci_registry_password != null ? var.oci_registry_username : null
  repository_password = var.oci_registry_password

  values = [yamlencode(local.merged_helm_values)]

  depends_on = [kubernetes_secret.polis]
}
