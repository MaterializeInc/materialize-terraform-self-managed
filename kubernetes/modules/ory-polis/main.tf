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

# RSA keypair used by Polis to sign OIDC tokens returned to upstream consumers
# (Kratos). Without these env vars Polis errors with "OAuth server not
# configured correctly for openid flow, check if JWT signing keys are loaded".
resource "tls_private_key" "openid_rsa" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

locals {
  namespace = var.create_namespace ? kubernetes_namespace.polis[0].metadata[0].name : var.namespace

  admin_api_keys    = var.admin_api_keys != null ? var.admin_api_keys : random_password.admin_api_keys[0].result
  nextauth_secret   = var.nextauth_secret != null ? var.nextauth_secret : random_password.nextauth_secret[0].result
  db_encryption_key = var.db_encryption_key != null ? var.db_encryption_key : random_password.db_encryption_key[0].result

  secret_name = "${var.release_name}-config"

  # Everything secret reaches the container through the chart's envFrom, never
  # through the Helm values, which the helm provider echoes in plan output.
  # OPENID_RSA_* are the OIDC token signing keys, base64 of the PEM so the env
  # var stays one line. The private key must be PKCS#8 (Polis rejects PKCS#1).
  secret_data = {
    DB_URL                  = var.dsn
    API_KEYS                = local.admin_api_keys
    NEXTAUTH_SECRET         = local.nextauth_secret
    POLIS_DB_ENCRYPTION_KEY = local.db_encryption_key
    OPENID_RSA_PRIVATE_KEY  = base64encode(tls_private_key.openid_rsa.private_key_pem_pkcs8)
    OPENID_RSA_PUBLIC_KEY   = base64encode(tls_private_key.openid_rsa.public_key_pem)
  }

  # Hash of the secret data surfaced as a pod annotation so updating any value
  # forces a rollout, since Kubernetes does not re-roll on Secret changes.
  secret_checksum = nonsensitive(sha256(jsonencode(local.secret_data)))

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

  # EXTERNAL_URL controls the host Polis advertises in SCIM endpoint URLs,
  # OAuth callbacks, and similar. Without it Polis falls back to its internal
  # listen address (http://localhost:5225) which IdPs can't reach.
  external_url_env = [{
    name  = "EXTERNAL_URL"
    value = var.external_url
  }]

  # The chart hardcodes OPENID_REDIRECT_EXACT_MATCH=true, so only append an
  # override (last-wins) when disabling it, to avoid a duplicate env by default.
  openid_redirect_exact_match_env = var.openid_redirect_exact_match ? [] : [{
    name  = "OPENID_REDIRECT_EXACT_MATCH"
    value = "false"
  }]

  extra_envs = concat(
    local.saml_audience_env,
    local.external_url_env,
    local.openid_redirect_exact_match_env,
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

  # Chart-provided nginx sidecar that terminates TLS in front of the plain-HTTP
  # Polis listener. When enabled the chart's Service routes to the sidecar on
  # tls_sidecar_port over HTTPS instead of hitting Polis directly.
  tls_sidecar_config = var.tls_secret_name != null ? {
    tlsSidecar = {
      enabled = true
      port    = var.tls_sidecar_port
      tls = {
        secretName = var.tls_secret_name
        certFile   = var.tls_cert_file
        keyFile    = var.tls_key_file
      }
    }
  } : {}

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
      # The chart hardcodes DB_ENCRYPTION_KEY as a literal env value, so point
      # it at the envFrom copy; the kubelet expands $(VAR) from envFrom vars.
      dbEncryptionKey = "$(POLIS_DB_ENCRYPTION_KEY)"
      nextAuthUrl     = var.external_url
      nextAuthAcl     = var.nextauth_acl
    }

    service = {
      port = var.port
      type = "ClusterIP"
    }

    deployment = {
      annotations = {
        "checksum/config" = local.secret_checksum
      }
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
  }, local.image_config, local.image_pull_secrets_config, local.monitoring_config, local.tls_sidecar_config)

  merged_helm_values = provider::deepmerge::mergo(local.default_helm_values, var.helm_values)
}

# Secret feeding the chart's envFrom. The chart's built-in secret template
# hardcodes a CockroachDB DSN, so we always disable it and provide our own
# with the Postgres DB_URL plus every other secret the container expects.
resource "kubernetes_secret" "polis" {
  metadata {
    name      = local.secret_name
    namespace = local.namespace
  }

  data = local.secret_data
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

# Internal-only ClusterIP fronting the TLS sidecar, so in-cluster clients (e.g.
# Kratos's Polis back-channel) can reach Polis at its public FQDN via a CoreDNS
# rewrite instead of hairpinning out to Polis's external LoadBalancer, which GKE
# pods cannot reach. Only created when the TLS sidecar is enabled. Pair it with a
# CoreDNS rewrite of the public FQDN to this service (see the ory-stack
# coredns_rewrites output).
resource "kubernetes_service_v1" "internal_tls" {
  count = var.tls_secret_name != null ? 1 : 0

  metadata {
    name      = "${var.release_name}-internal"
    namespace = local.namespace
    labels = {
      "app.kubernetes.io/name"     = "polis"
      "app.kubernetes.io/instance" = var.release_name
      "provisioned-by"             = "materialize"
    }
  }

  spec {
    type = "ClusterIP"

    selector = {
      "app.kubernetes.io/name"     = "polis"
      "app.kubernetes.io/instance" = var.release_name
    }

    port {
      name        = "https"
      port        = 443
      target_port = var.tls_sidecar_port
    }
  }

  depends_on = [helm_release.polis]
}
