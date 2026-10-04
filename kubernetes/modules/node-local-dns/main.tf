# NodeLocal DNSCache (deliveryhero chart). A DaemonSet on every node, tainted
# Materialize pools included, answers pod DNS on-node by binding the kube-dns
# ClusterIP locally with NOTRACK iptables rules.
#
# Needs kube-proxy in iptables mode (e.g. EKS). eBPF dataplanes (GKE Dataplane
# V2, AKS with Cilium) rewrite the ClusterIP before iptables sees it; on GKE use
# the NodeLocal DNSCache addon (dns_cache_config) instead.
locals {
  # The chart's Corefile, but with cluster-zone cache TTLs that keep ../coredns's
  # TTL 0 (fresh pod IPs during rollouts) instead of caching for 30s. node-cache
  # fills in the __PILLAR__ placeholders at startup.
  #
  # Host network: binding the wildcard collides with other port 53 listeners
  # (Bottlerocket has one: https://github.com/bottlerocket-os/bottlerocket/issues/3711),
  # so bind only the link-local IP and the kube-dns ClusterIP.
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
  # Singleton per cluster, so no name prefix.
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
      # Scrapes `prometheus :9253` per node. The chart does not check for the
      # monitoring.coreos.com API and always puts the monitor in kube-system.
      serviceMonitor = {
        enabled = var.enable_service_monitor
      }
    })
  ]
}
