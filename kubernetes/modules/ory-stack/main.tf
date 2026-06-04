locals {
  # When materialize_namespace is set, the module wires Materialize-side resources
  # (OAuth2 client, network policies, console LB). When null, those are skipped.
  wire_materialize = var.materialize_namespace != null

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
  ui_external_url     = "https://${var.ui_fqdn}"
  polis_external_url  = local.wire_polis ? "https://${var.polis_fqdn}" : null

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
  # emitted by the upstream charts.
  ory_lb_services = merge({
    kratos-public-lb = {
      app_name     = "kratos"
      app_instance = "kratos"
      target_port  = 4433
    }
    hydra-public-lb = {
      app_name     = "hydra"
      app_instance = "hydra"
      target_port  = 4444
    }
    ory-selfservice-ui-lb = {
      app_name     = "kratos-selfservice-ui-node"
      app_instance = module.ory_selfservice_ui.service_name
      target_port  = module.ory_selfservice_ui.port
    }
    }, local.wire_polis ? {
    polis-public-lb = {
      app_name     = "polis-tls-proxy"
      app_instance = "polis"
      target_port  = 8443
    }
  } : {})

  # cert-manager Certificate map for the browser-facing services. Polis is added
  # when enabled. Polis does not terminate TLS itself, so the cert is consumed by
  # the LB Service's TLS termination rather than mounted into the pod.
  ory_certs = merge({
    hydra-tls              = { fqdn = var.hydra_fqdn, cluster_svc = "hydra-public.${var.namespace}.svc.cluster.local" }
    kratos-tls             = { fqdn = var.kratos_fqdn, cluster_svc = "kratos-public.${var.namespace}.svc.cluster.local" }
    ory-selfservice-ui-tls = { fqdn = var.ui_fqdn, cluster_svc = null }
    }, local.wire_polis ? {
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
          flows = {
            login        = { ui_url = "${local.ui_external_url}/login" }
            registration = { ui_url = "${local.ui_external_url}/registration" }
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

  image_repository   = "${var.oel_registry}/ory-enterprise/hydra-oel"
  image_tag          = var.oel_image_tag
  image_pull_secrets = [kubernetes_secret.ory_oel_registry.metadata[0].name]

  tls_cert_secret_name = "hydra-tls"

  cors_allowed_origins = local.wire_materialize ? ["https://${var.materialize_console_fqdn}"] : []

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
    kubectl_manifest.ory_certificate["ory-selfservice-ui-tls"],
  ]
}

# Ory Polis (optional) -------------------------------------------------------

# Polis is a SAML-to-OIDC bridge: it accepts a customer's SAML IdP on one side
# and exposes an OIDC provider on the other. Kratos can consume it as an
# upstream OIDC provider for social sign-in.
#
# Image pull always goes through the Materialize OEL registry proxy with the
# license-key JWT (same imagePullSecret as Kratos/Hydra). Chart pull defaults
# to that proxy too, but the proxy does not yet serve OCI chart manifests, so
# callers can override polis_chart_{registry,repository,oci_*} to pull the
# chart directly from GCP Artifact Registry with a service-account key.
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

  node_selector = var.node_selector

  helm_values = var.polis_helm_values

  depends_on = [
    kubernetes_namespace.ory,
    kubernetes_secret.ory_oel_registry,
  ]
}

# Polis TLS-terminating proxy (only when enable_polis is true) ---------------

# Polis is a NextJS app that doesn't terminate TLS itself, and the polis-oel
# chart doesn't expose a sidecar/extraContainers hook. We front it with a
# minimal nginx-unprivileged Deployment that mounts the polis-tls cert and
# reverse-proxies to the in-cluster polis ClusterIP Service. The public LB
# Service then targets these proxy pods on port 8443.

resource "kubernetes_config_map_v1" "polis_tls_proxy" {
  count = local.wire_polis ? 1 : 0

  metadata {
    name      = "polis-tls-proxy"
    namespace = var.namespace
  }

  data = {
    "nginx.conf" = <<-EOT
      worker_processes auto;
      error_log /tmp/error.log warn;
      pid /tmp/nginx.pid;
      events { worker_connections 1024; }
      http {
        client_body_temp_path /tmp/client_body;
        proxy_temp_path       /tmp/proxy;
        fastcgi_temp_path     /tmp/fastcgi;
        uwsgi_temp_path       /tmp/uwsgi;
        scgi_temp_path        /tmp/scgi;

        server {
          listen 8443 ssl;
          http2 on;

          ssl_certificate     /etc/nginx/tls/tls.crt;
          ssl_certificate_key /etc/nginx/tls/tls.key;
          ssl_protocols       TLSv1.2 TLSv1.3;

          location / {
            proxy_pass http://polis.${var.namespace}.svc.cluster.local:5225;
            proxy_set_header Host              $host;
            proxy_set_header X-Real-IP         $remote_addr;
            proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
            proxy_http_version 1.1;
          }
        }
      }
    EOT
  }
}

resource "kubernetes_deployment_v1" "polis_tls_proxy" {
  count = local.wire_polis ? 1 : 0

  metadata {
    name      = "polis-tls-proxy"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"     = "polis-tls-proxy"
      "app.kubernetes.io/instance" = "polis"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        "app.kubernetes.io/name"     = "polis-tls-proxy"
        "app.kubernetes.io/instance" = "polis"
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name"     = "polis-tls-proxy"
          "app.kubernetes.io/instance" = "polis"
        }
        annotations = {
          # Force a rollout when the nginx config changes.
          "checksum/config" = sha256(kubernetes_config_map_v1.polis_tls_proxy[0].data["nginx.conf"])
        }
      }

      spec {
        node_selector = var.node_selector

        container {
          name              = "nginx"
          image             = "nginxinc/nginx-unprivileged:1.27-alpine"
          image_pull_policy = "IfNotPresent"

          port {
            name           = "https"
            container_port = 8443
          }

          volume_mount {
            name       = "tls"
            mount_path = "/etc/nginx/tls"
            read_only  = true
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/nginx/nginx.conf"
            sub_path   = "nginx.conf"
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "32Mi"
            }
            limits = {
              memory = "64Mi"
            }
          }

          readiness_probe {
            tcp_socket {
              port = 8443
            }
            initial_delay_seconds = 2
            period_seconds        = 5
          }
        }

        volume {
          name = "tls"
          secret {
            secret_name = "polis-tls"
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map_v1.polis_tls_proxy[0].metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [
    module.ory_polis,
    kubectl_manifest.ory_certificate["polis-tls"],
  ]
}

# Public LoadBalancers (Kratos public, Hydra public, selfservice UI, Polis) --

resource "kubernetes_service_v1" "ory_lb" {
  for_each = local.ory_lb_services

  metadata {
    name        = each.key
    namespace   = var.namespace
    annotations = var.lb_annotations
  }

  spec {
    type                    = "LoadBalancer"
    load_balancer_class     = var.lb_load_balancer_class
    external_traffic_policy = var.lb_external_traffic_policy

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

  depends_on = [
    module.ory_kratos,
    module.ory_hydra,
    module.ory_polis,
    kubernetes_deployment_v1.polis_tls_proxy,
  ]
}

# -----------------------------------------------------------------------------
# Materialize integration (gated by var.materialize_namespace)
# -----------------------------------------------------------------------------

# Materialize console HTTPS LoadBalancer. The console redirects away from
# non-canonical ports so OIDC needs the browser to hit it on 443.
resource "kubernetes_service_v1" "console_https_lb" {
  count = local.wire_materialize ? 1 : 0

  metadata {
    name        = "${var.materialize_instance_name}-console-https"
    namespace   = var.materialize_namespace
    annotations = var.lb_annotations
  }

  spec {
    type                    = "LoadBalancer"
    load_balancer_class     = var.lb_load_balancer_class
    external_traffic_policy = var.lb_external_traffic_policy

    selector = {
      "materialize.cloud/app"                    = "console"
      "materialize.cloud/mz-resource-id"         = var.materialize_instance_resource_id
      "materialize.cloud/organization-name"      = var.materialize_instance_name
      "materialize.cloud/organization-namespace" = var.materialize_namespace
    }

    port {
      name        = "https"
      port        = 443
      target_port = 8080
      protocol    = "TCP"
    }
  }

  wait_for_load_balancer = true
}

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
      redirectUris  = ["https://${var.materialize_console_fqdn}/auth/callback"]
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

# Network policies bridging materialize <-> ory namespaces -------------------

resource "kubernetes_network_policy_v1" "materialize_to_ory_egress" {
  count = local.wire_materialize ? 1 : 0

  metadata {
    name      = "allow-ory-egress"
    namespace = var.materialize_namespace
  }

  spec {
    pod_selector {}
    policy_types = ["Egress"]

    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = var.namespace
          }
        }
      }
    }
  }

  # Wait for the materialize namespace to exist. console_https_lb already
  # depends on var.materialize_instance_resource_id (which references the
  # caller's materialize_instance module), so this chains the dep without
  # the module having to know about materialize_instance directly.
  depends_on = [kubernetes_service_v1.console_https_lb]
}

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
