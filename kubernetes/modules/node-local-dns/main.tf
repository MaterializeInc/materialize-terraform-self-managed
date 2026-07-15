# NodeLocal DNSCache deployed via the deliveryhero helm chart.
#
# Runs a node-cache DaemonSet on every node (the chart's built-in tolerations
# tolerate all NoSchedule/NoExecute taints plus CriticalAddonsOnly, so it also
# lands on the tainted Materialize node pools). Each pod binds the kube-dns
# ClusterIP on a local dummy interface and installs NOTRACK iptables rules, so
# pod DNS queries are answered on-node without conntrack or a network hop.
#
# This only works where services are resolved by kube-proxy in iptables mode
# (e.g. EKS). On eBPF dataplanes (GKE Dataplane V2, AKS with Cilium) the
# kube-dns ClusterIP is rewritten in eBPF before iptables sees it, so this
# module cannot intercept DNS there. For GKE use the built-in NodeLocal
# DNSCache addon (dns_cache_config) instead.
locals {
  # Corefile for node-local-dns. Mirrors the chart's generated config except
  # for the cluster-zone cache TTLs: the custom CoreDNS deployment (see
  # ../coredns) serves records with TTL 0 so Materialize sees fresh pod IPs
  # during rollouts, and the chart's default 30s node-local cache would
  # reintroduce that staleness. __PILLAR__CLUSTER__DNS__ and
  # __PILLAR__UPSTREAM__SERVERS__ are substituted by the node-cache binary at
  # startup.
  #
  # The DaemonSet runs on the host network, so binding the wildcard address
  # collides with anything else listening on port 53 on the node (Bottlerocket
  # hosts already have a listener there, crashing the pod; see
  # https://github.com/bottlerocket-os/bottlerocket/issues/3711). Bind only the
  # link-local IP and the kube-dns ClusterIP, both of which node-cache sets up
  # on a local dummy interface.
  bind_ips = "${var.local_dns_ip} ${var.dns_server}"

  corefile = <<-EOF
    ${var.cluster_domain}:53 {
        errors
        cache {
                success 9984 ${var.cluster_cache_ttl}
                denial 9984 ${var.cluster_cache_ttl}
        }
        reload
        loop
        bind ${local.bind_ips}
        forward . __PILLAR__CLUSTER__DNS__ {
                force_tcp
        }
        prometheus :9253
        health :8080
        }
    in-addr.arpa:53 {
        errors
        cache ${var.cluster_cache_ttl}
        reload
        loop
        bind ${local.bind_ips}
        forward . __PILLAR__CLUSTER__DNS__ {
                force_tcp
        }
        prometheus :9253
        }
    ip6.arpa:53 {
        errors
        cache ${var.cluster_cache_ttl}
        reload
        loop
        bind ${local.bind_ips}
        forward . __PILLAR__CLUSTER__DNS__ {
                force_tcp
        }
        prometheus :9253
        }
    .:53 {
        errors
        cache ${var.upstream_cache_ttl}
        reload
        loop
        bind ${local.bind_ips}
        forward . __PILLAR__UPSTREAM__SERVERS__
        prometheus :9253
        }
  EOF
}

resource "helm_release" "node_local_dns" {
  # node-local-dns is a singleton resource for the cluster,
  # so not using name prefixes here.
  name       = "node-local-dns"
  namespace  = var.namespace
  repository = "https://charts.deliveryhero.io"
  chart      = "node-local-dns"
  version    = var.chart_version
  timeout    = var.install_timeout

  values = [
    yamlencode({
      fullnameOverride = "node-local-dns"
      config = {
        dnsDomain = var.cluster_domain
        dnsServer = var.dns_server
        localDns  = var.local_dns_ip
        # bindIp only affects the chart's generated Corefile, which
        # customConfig replaces; set for consistency with the bind lines above.
        bindIp       = true
        customConfig = local.corefile
      }
      resources = {
        limits = {
          memory = var.memory_limit
        }
        requests = {
          cpu    = var.cpu_request
          memory = var.memory_request
        }
      }
    })
  ]
}
