locals {
  # When set, the module creates the OAuth2 client CRD and the ory-side ingress
  # policy from the materialize namespace. Null skips Materialize integration.
  wire_materialize = var.materialize_namespace != null

  # Every browser origin the console is served on: the primary FQDN plus any
  # extras (e.g. a VPN or tailnet hostname fronting the same pods). Feeds the
  # OAuth2 redirect URIs, post-logout URIs, and Hydra CORS, so sign-in works
  # from each origin.
  materialize_console_fqdns = concat(
    var.materialize_console_fqdn != null ? [var.materialize_console_fqdn] : [],
    var.materialize_console_extra_fqdns,
  )

  # Polis is optional and gated by var.enable_polis.
  wire_polis = var.enable_polis

  # Hostname portion of var.oel_registry (everything before the first '/').
  # Used as the dockerconfigjson auths key on the imagePullSecret, and as the
  # image.registry / chart_registry for Polis (whose chart takes registry and
  # repository as separate fields).
  oel_registry_host = split("/", var.oel_registry)[0]

  # Full image and chart repository paths for Polis, derived from oel_registry.
  # The Polis chart takes image.registry and image.repository separately, so we
  # split the host off before passing them through.
  polis_image_full       = "${var.oel_registry}/ory-enterprise-polis/polis-oel"
  polis_image_repository = trimprefix(local.polis_image_full, "${local.oel_registry_host}/")
  polis_chart_full       = "${var.oel_registry}/helm-oel-polis/polis-oel"
  polis_chart_repository = trimprefix(local.polis_chart_full, "${local.oel_registry_host}/")

  # External URLs that the browser (and Materialize, for OIDC issuer matching)
  # sees. FQDNs resolve to the LB IPs and are terminated by cert-manager certs.
  # No trailing slash on any of them: matters for OIDC issuer-string comparison
  # downstream, which is exact-match.
  hydra_external_url  = "https://${var.hydra_fqdn}"
  kratos_external_url = "https://${var.kratos_fqdn}"
  # The standalone UI FQDN when we deploy it, otherwise the external URL of
  # whatever app hosts the Ory flow pages (e.g. the console). Kratos and Hydra
  # redirect the browser here for login/consent/etc.
  ui_external_url    = var.deploy_selfservice_ui ? "https://${var.ui_fqdn}" : var.selfservice_ui_url
  polis_external_url = local.wire_polis ? "https://${var.polis_fqdn}" : null

  # Cookie domain shared across the Ory subdomains so flow/session cookies work
  # across sibling FQDNs (Kratos, UI, Hydra). Defaults to the parent domain of
  # kratos_fqdn (e.g. kratos.example.com -> example.com); when kratos_fqdn is a
  # single label (no '.') we fall back to the value itself rather than erroring.
  kratos_fqdn_parts = split(".", var.kratos_fqdn)
  cookie_parent_domain = (
    var.cookie_parent_domain != null
    ? var.cookie_parent_domain
    : (
      length(local.kratos_fqdn_parts) > 1
      ? join(".", slice(local.kratos_fqdn_parts, 1, length(local.kratos_fqdn_parts)))
      : var.kratos_fqdn
    )
  )

  # In-cluster admin URL for Hydra. Used by Kratos (oauth2_provider.url) and the
  # selfservice UI (HYDRA_ADMIN_URL). Hardcoded service hostname because the
  # Hydra Helm chart deploys with this canonical service name.
  hydra_admin_internal_url = "http://hydra-admin.${var.namespace}.svc.cluster.local:4445"

  # Public LoadBalancer Service map (Kratos public, Hydra public, selfservice UI,
  # and Polis when enabled). Selectors target the app.kubernetes.io/* labels
  # emitted by the upstream charts. role is the key callers use in lb_overrides,
  # matching the lb_addresses output keys.
  ory_lb_services = merge({
    kratos-public-lb = {
      role         = "kratos"
      app_name     = "kratos"
      app_instance = "kratos"
      target_port  = 4433
    }
    hydra-public-lb = {
      role         = "hydra"
      app_name     = "hydra"
      app_instance = "hydra"
      target_port  = 4444
    }
    },
    var.deploy_selfservice_ui ? {
      ory-selfservice-ui-lb = {
        role         = "ui"
        app_name     = "kratos-selfservice-ui-node"
        app_instance = module.ory_selfservice_ui[0].service_name
        target_port  = module.ory_selfservice_ui[0].port
      }
    } : {},
    local.wire_polis ? {
      polis-public-lb = {
        role         = "polis"
        app_name     = "polis"
        app_instance = "polis"
        target_port  = 8443
      }
  } : {})

  # cert-manager Certificate map for the browser-facing services. Polis is added
  # when enabled and its cert is mounted into the chart's TLS-terminating nginx
  # sidecar.
  ory_certs = merge({
    hydra-tls  = { fqdn = var.hydra_fqdn, cluster_svc = "hydra-public.${var.namespace}.svc.cluster.local" }
    kratos-tls = { fqdn = var.kratos_fqdn, cluster_svc = "kratos-public.${var.namespace}.svc.cluster.local" }
    },
    var.deploy_selfservice_ui ? {
      ory-selfservice-ui-tls = { fqdn = var.ui_fqdn, cluster_svc = null }
    } : {},
    local.wire_polis ? {
      polis-tls = { fqdn = var.polis_fqdn, cluster_svc = null }
  } : {})

  # Baked-in Kratos config that the enterprise setup requires. Callers can
  # override individual keys via var.kratos_helm_values (deep-merged on top).
  kratos_helm_values_baseline = {
    kratos = {
      config = {
        serve = {
          public = {
            base_url = local.kratos_external_url
          }
        }
        cookies = {
          domain    = local.cookie_parent_domain
          same_site = "Lax"
        }
        session = {
          cookie = {
            domain    = local.cookie_parent_domain
            same_site = "Lax"
          }
        }
        oauth2_provider = {
          url = local.hydra_admin_internal_url
        }
        selfservice = {
          default_browser_return_url = local.ui_external_url
          # SSO-only: disable local password login/registration and profile
          # self-edits so users cannot set their own traits (e.g. groups).
          # OIDC stays enabled, so IdP just-in-time provisioning still works.
          methods = {
            password = { enabled = false }
            profile  = { enabled = false }
          }
          flows = {
            login = { ui_url = "${local.ui_external_url}/login" }
            # session hook logs the user in on first OIDC registration; without
            # it Hydra consent gets no identity and the JWT has no email claim.
            registration = {
              ui_url = "${local.ui_external_url}/registration"
              after  = { oidc = { hooks = [{ hook = "session" }] } }
            }
            recovery     = { ui_url = "${local.ui_external_url}/recovery" }
            verification = { ui_url = "${local.ui_external_url}/verification" }
            settings     = { ui_url = "${local.ui_external_url}/settings" }
            error        = { ui_url = "${local.ui_external_url}/error" }
            logout       = { after = { default_browser_return_url = local.ui_external_url } }
          }
        }
        identity = {
          default_schema_id = "default"
          schemas = [
            {
              id  = "default"
              url = "file:///etc/config/identity.default.schema.json"
            }
          ]
        }
      }
    }
  }

  # JWT access tokens so Materialize can validate locally against the JWKS.
  hydra_helm_values_baseline = {
    hydra = {
      config = {
        strategies = {
          access_token = "jwt"
        }
      }
    }
  }
}

# Namespace -------------------------------------------------------------------

resource "kubernetes_namespace" "ory" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
  }
}

# Image pull secret for the Ory registry proxy --------------------------------

# The proxy validates the license-key JWT, checks the ory entitlement, and
# forwards to Ory's Artifact Registry using Materialize's service account.
# Username is arbitrary; the proxy ignores it. Convention: "jwt".
# Pods need egress to the proxy host AND storage.googleapis.com (the proxy
# returns 307 redirects to signed GCS URLs for blob GETs, which the kubelet
# follows directly).
resource "kubernetes_secret" "ory_oel_registry" {
  metadata {
    name      = var.oel_registry_secret_name
    namespace = var.namespace
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        (local.oel_registry_host) = {
          auth = base64encode("jwt:${var.license_key_jwt}")
        }
      }
    })
  }

  depends_on = [kubernetes_namespace.ory]
}

# Browser-facing TLS certificates --------------------------------------------

# The optional *.cluster.local SAN is dropped when the customer brings their own
# (potentially public ACME) issuer that can't sign single-label cluster names;
# in that case in-cluster callers route via the public hostname (hairpin NAT
# through the LB; TLS still validates).
resource "kubectl_manifest" "ory_certificate" {
  for_each = local.ory_certs

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = each.key
      namespace = var.namespace
    }
    spec = {
      secretName = each.key
      dnsNames = concat(
        [each.value.fqdn],
        var.cert_issuer_signs_cluster_local && each.value.cluster_svc != null ? [each.value.cluster_svc] : [],
      )
      issuerRef = var.cert_issuer_ref
    }
  })

  depends_on = [kubernetes_namespace.ory]
}

# Ory Kratos -----------------------------------------------------------------

module "ory_kratos" {
  source = "../ory-kratos"

  namespace        = var.namespace
  create_namespace = false
  dsn              = var.kratos_dsn

  secrets_default = var.kratos_secrets_default
  secrets_cookie  = var.kratos_secrets_cookie
  secrets_cipher  = var.kratos_secrets_cipher

  image_repository   = "${var.oel_registry}/ory-enterprise-kratos/kratos-oel"
  image_tag          = var.oel_image_tag
  image_pull_secrets = [kubernetes_secret.ory_oel_registry.metadata[0].name]

  tls_cert_secret_name = "kratos-tls"

  node_selector = var.node_selector

  identity_schemas = {
    "identity.default.schema.json" = jsonencode({
      "$id"     = "https://schemas.ory.sh/presets/kratos/identity.basic.schema.json"
      "$schema" = "http://json-schema.org/draft-07/schema#"
      title     = "Default Identity Schema"
      type      = "object"
      properties = {
        traits = {
          type = "object"
          properties = {
            email = {
              type   = "string"
              format = "email"
              title  = "Email"
              "ory.sh/kratos" = {
                credentials = {
                  password = { identifier = true }
                }
                recovery     = { via = "email" }
                verification = { via = "email" }
              }
            }
            groups = {
              type  = "array"
              title = "Groups"
              items = { type = "string" }
            }
          }
          required = ["email"]
        }
      }
    })
  }

  helm_values = provider::deepmerge::mergo(local.kratos_helm_values_baseline, var.kratos_helm_values)

  upstream_oidc_providers = var.upstream_oidc_providers

  depends_on = [
    kubernetes_namespace.ory,
    kubernetes_secret.ory_oel_registry,
    kubectl_manifest.ory_certificate["kratos-tls"],
  ]
}

# Ory Hydra ------------------------------------------------------------------

module "ory_hydra" {
  source = "../ory-hydra"

  namespace        = var.namespace
  create_namespace = false

  dsn        = var.hydra_dsn
  issuer_url = local.hydra_external_url

  secrets_system = var.hydra_secrets_system
  secrets_cookie = var.hydra_secrets_cookie

  image_repository   = "${var.oel_registry}/ory-enterprise/hydra-oel"
  image_tag          = var.oel_image_tag
  image_pull_secrets = [kubernetes_secret.ory_oel_registry.metadata[0].name]

  tls_cert_secret_name = "hydra-tls"

  cors_allowed_origins = local.wire_materialize ? [for fqdn in local.materialize_console_fqdns : "https://${fqdn}"] : []

  login_url   = "${local.ui_external_url}/login"
  consent_url = "${local.ui_external_url}/consent"
  logout_url  = "${local.ui_external_url}/logout"

  helm_values = provider::deepmerge::mergo(local.hydra_helm_values_baseline, var.hydra_helm_values)

  node_selector = var.node_selector

  depends_on = [
    module.ory_kratos,
    kubernetes_namespace.ory,
    kubernetes_secret.ory_oel_registry,
    kubectl_manifest.ory_certificate["hydra-tls"],
  ]
}

# Ory selfservice UI ---------------------------------------------------------

# Sits between Hydra and Kratos. Hydra has no built-in way to authenticate
# users or collect consent; the UI fills both roles.
module "ory_selfservice_ui" {
  source = "../ory-selfservice-ui"
  count  = var.deploy_selfservice_ui ? 1 : 0

  namespace = var.namespace

  # Server-side calls from the UI pod to Kratos's public API. When the issuer
  # signs cluster.local hostnames (self-signed default) we can use the in-cluster
  # service URL directly. Otherwise the cert only covers the external hostname,
  # so we hairpin out through the LB.
  kratos_public_url  = var.cert_issuer_signs_cluster_local ? module.ory_kratos.public_url : local.kratos_external_url
  kratos_admin_url   = module.ory_kratos.admin_url
  kratos_browser_url = local.kratos_external_url
  hydra_admin_url    = local.hydra_admin_internal_url

  tls_cert_secret_name = "ory-selfservice-ui-tls"

  # Only needed when Kratos/Hydra are served by the in-cluster self-signed CA.
  trust_mounted_ca_cert = var.cert_issuer_signs_cluster_local

  node_selector = var.node_selector
  extra_env     = var.selfservice_ui_extra_env

  depends_on = [
    kubectl_manifest.ory_certificate,
  ]
}

# Ory Polis (optional) -------------------------------------------------------

# Polis is a SAML-to-OIDC bridge: it accepts a customer's SAML IdP on one side
# and exposes an OIDC provider on the other. Kratos can consume it as an
# upstream OIDC provider for social sign-in.
#
# Image and chart are both pulled through the Materialize OEL registry proxy
# with the license-key JWT (same auth flow as Kratos/Hydra images). Callers
# can override polis_chart_{registry,repository,oci_*} to pull the chart from
# a different OCI registry if they want to bypass the proxy.
module "ory_polis" {
  count = local.wire_polis ? 1 : 0

  source = "../ory-polis"

  namespace        = var.namespace
  create_namespace = false

  dsn          = var.polis_dsn
  external_url = local.polis_external_url

  chart_registry        = var.polis_chart_registry != null ? var.polis_chart_registry : local.oel_registry_host
  chart_repository      = var.polis_chart_repository != null ? var.polis_chart_repository : local.polis_chart_repository
  chart_version         = var.polis_chart_version
  oci_registry_username = var.polis_chart_oci_username
  oci_registry_password = var.polis_chart_oci_password != null ? var.polis_chart_oci_password : var.license_key_jwt

  image_registry     = local.oel_registry_host
  image_repository   = local.polis_image_repository
  image_tag          = var.polis_oel_image_tag
  image_pull_secrets = [kubernetes_secret.ory_oel_registry.metadata[0].name]

  admin_api_keys    = var.polis_admin_api_keys
  nextauth_secret   = var.polis_nextauth_secret
  db_encryption_key = var.polis_db_encryption_key

  # cert-manager Secret consumed by the chart's TLS-terminating nginx sidecar.
  # Matches the Certificate created for the polis-tls entry in ory_certs above.
  tls_secret_name = "polis-tls"

  node_selector = var.node_selector

  helm_values = var.polis_helm_values

  depends_on = [
    kubernetes_namespace.ory,
    kubernetes_secret.ory_oel_registry,
    kubectl_manifest.ory_certificate["polis-tls"],
  ]
}

# Public LoadBalancers (Kratos public, Hydra public, selfservice UI, Polis) --

resource "kubernetes_service_v1" "ory_lb" {
  for_each = local.ory_lb_services

  metadata {
    name        = each.key
    namespace   = var.namespace
    annotations = merge(var.lb_annotations, try(var.lb_overrides[each.value.role].annotations, {}))
  }

  spec {
    type                    = "LoadBalancer"
    load_balancer_class     = var.lb_load_balancer_class
    external_traffic_policy = var.lb_external_traffic_policy
    # Enforced by the cloud controller in the provider firewall, so it applies
    # even when the cluster datapath ignores NetworkPolicy (see lb_source_cidrs).
    load_balancer_source_ranges = try(var.lb_overrides[each.value.role].source_ranges, null)

    selector = {
      "app.kubernetes.io/name"     = each.value.app_name
      "app.kubernetes.io/instance" = each.value.app_instance
    }

    port {
      name        = "https"
      port        = 443
      target_port = each.value.target_port
      protocol    = "TCP"
    }
  }

  wait_for_load_balancer = true

  lifecycle {
    ignore_changes = [
      metadata[0].annotations["networking.gke.io/target-pool"],
      metadata[0].annotations["cloud.google.com/neg"],
    ]
  }

  depends_on = [
    module.ory_kratos,
    module.ory_hydra,
    module.ory_polis,
  ]
}

# -----------------------------------------------------------------------------
# Materialize integration (gated by var.materialize_namespace)
# -----------------------------------------------------------------------------

# OAuth2Client CRD: Hydra Maester watches for these and creates/manages the
# OAuth2 client via Hydra's admin API. The Secret named here is populated by
# Hydra Maester with the generated client_id and client_secret.
resource "kubectl_manifest" "materialize_oauth2_client" {
  count = local.wire_materialize ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "hydra.ory.sh/v1alpha1"
    kind       = "OAuth2Client"
    metadata = {
      name      = var.oauth2_client_name
      namespace = var.namespace
    }
    spec = {
      clientName = "Materialize"
      grantTypes = [
        "authorization_code",
        "refresh_token",
      ]
      responseTypes = ["code", "id_token"]
      scope         = var.oauth2_client_scope
      audience      = var.oauth2_client_audience
      redirectUris  = [for fqdn in local.materialize_console_fqdns : "https://${fqdn}/auth/callback"]
      postLogoutRedirectUris = var.oauth2_client_post_logout_redirect_uris != null ? var.oauth2_client_post_logout_redirect_uris : [
        for fqdn in local.materialize_console_fqdns : "https://${fqdn}/"
      ]
      # First-party SPA client, no third-party consent needed. Skipping the
      # consent screen also avoids the first-login footgun where users click
      # Allow without ticking the email scope, leaving Materialize without the
      # auth claim it expects.
      skipConsent = true
      # Public SPA client. No secret; PKCE on the console side.
      secretName              = var.oauth2_client_name
      tokenEndpointAuthMethod = "none"
    }
  })

  depends_on = [module.ory_hydra]
}

# Read back the Hydra-Maester-populated client credentials so the caller can
# wire client_id into Materialize's system_parameters.
data "kubernetes_secret_v1" "oauth2_client" {
  count = local.wire_materialize ? 1 : 0

  metadata {
    name      = var.oauth2_client_name
    namespace = var.namespace
  }

  depends_on = [kubectl_manifest.materialize_oauth2_client]
}

# Network policies. The materialize -> ory egress policy is owned by the
# materialize-instance module (it lives in the materialize namespace).

# Allow Ory pods to receive traffic from Materialize, from within the ory
# namespace, and from external sources on the three public ports.
resource "kubernetes_network_policy_v1" "ory_from_materialize_ingress" {
  count = local.wire_materialize ? 1 : 0

  metadata {
    name      = "allow-ory-ingress"
    namespace = var.namespace
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = var.materialize_namespace
          }
        }
      }

      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = var.namespace
          }
        }
      }
    }

    # External traffic from the LBs hits Hydra public (4444), Kratos public
    # (4433), the selfservice UI (3000), and the Polis TLS proxy (8443, when
    # enabled). Admin ports stay internal.
    ingress {
      dynamic "from" {
        for_each = var.lb_source_cidrs
        content {
          ip_block {
            cidr = from.value
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = 4444
      }
      ports {
        protocol = "TCP"
        port     = 4433
      }
      ports {
        protocol = "TCP"
        port     = 3000
      }
      dynamic "ports" {
        for_each = local.wire_polis ? [1] : []
        content {
          protocol = "TCP"
          port     = 8443
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.ory]
}
