# Optional Ory identity stack: Kratos, Hydra, the selfservice UI and Polis,
# turned on with enable_ory. Its Services are ClusterIP and its hostnames are
# those Services' in-cluster names, so it is reachable only from inside the
# cluster; put your own ingress or load balancer in front to sign in from a
# browser. Materialize keeps password authentication in this example.

locals {
  ory_namespace = "ory"

  # The ory-stack module names its Services <role>-lb, whatever their type.
  ory_hosts = {
    hydra  = "hydra-public-lb.${local.ory_namespace}.svc.cluster.local"
    kratos = "kratos-public-lb.${local.ory_namespace}.svc.cluster.local"
    ui     = "ory-selfservice-ui-lb.${local.ory_namespace}.svc.cluster.local"
    polis  = "polis-public-lb.${local.ory_namespace}.svc.cluster.local"
  }
}

module "ory" {
  source = "../../modules/ory-stack"
  count  = var.enable_ory ? 1 : 0

  namespace    = local.ory_namespace
  service_type = "ClusterIP"

  hydra_fqdn  = local.ory_hosts.hydra
  kratos_fqdn = local.ory_hosts.kratos
  ui_fqdn     = local.ory_hosts.ui
  # Kratos and the selfservice UI are on different hosts, so their cookies
  # need a domain that covers both.
  kratos_cookie_domain = "${local.ory_namespace}.svc.cluster.local"

  kratos_dsn = var.ory_kratos_dsn
  hydra_dsn  = var.ory_hydra_dsn

  enable_polis = var.ory_enable_polis
  polis_fqdn   = var.ory_enable_polis ? local.ory_hosts.polis : null
  polis_dsn    = var.ory_enable_polis ? var.ory_polis_dsn : null

  license_key_jwt = var.license_key

  cert_issuer_ref = {
    name = module.self_signed_cluster_issuer.issuer_name
    kind = "ClusterIssuer"
  }
  cert_issuer_signs_cluster_local = true

  # Registers the OAuth2 client the Materialize console would sign in with.
  materialize_namespace    = module.materialize_instance.instance_namespace
  materialize_console_fqdn = "mz${module.materialize_instance.instance_resource_id}-console.${module.materialize_instance.instance_namespace}.svc.cluster.local"

  depends_on = [module.self_signed_cluster_issuer]
}
