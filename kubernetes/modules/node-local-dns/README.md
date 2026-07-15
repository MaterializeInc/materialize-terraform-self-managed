## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 2.5.0, < 2.18.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_helm"></a> [helm](#provider\_helm) | >= 2.5.0, < 2.18.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [helm_release.node_local_dns](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_chart_version"></a> [chart\_version](#input\_chart\_version) | Version of the node-local-dns helm chart to install. | `string` | `"2.1.0"` | no |
| <a name="input_cluster_cache_ttl"></a> [cluster\_cache\_ttl](#input\_cluster\_cache\_ttl) | Cache TTL in seconds for the cluster DNS zones (cluster domain and reverse zones). Kept at 1s to avoid stale pod IPs during Materialize rollouts, matching the TTL-0 intent of the custom CoreDNS deployment while still absorbing query floods. | `number` | `1` | no |
| <a name="input_cluster_domain"></a> [cluster\_domain](#input\_cluster\_domain) | Internal Kubernetes DNS domain. | `string` | `"cluster.local"` | no |
| <a name="input_cpu_request"></a> [cpu\_request](#input\_cpu\_request) | CPU request for the node-cache container. | `string` | `"25m"` | no |
| <a name="input_dns_server"></a> [dns\_server](#input\_dns\_server) | ClusterIP of the kube-dns service. node-local-dns binds this IP on a local dummy interface to intercept pod DNS traffic (iptables mode). On EKS this is the .10 address of the cluster service CIDR. | `string` | n/a | yes |
| <a name="input_install_timeout"></a> [install\_timeout](#input\_install\_timeout) | Timeout for installing the node-local-dns helm chart, in seconds. | `number` | `300` | no |
| <a name="input_local_dns_ip"></a> [local\_dns\_ip](#input\_local\_dns\_ip) | Link-local IP that node-local-dns additionally binds. Only used as --cluster-dns in IPVS mode; must not collide with anything. | `string` | `"169.254.20.25"` | no |
| <a name="input_memory_limit"></a> [memory\_limit](#input\_memory\_limit) | Memory limit for the node-cache container. | `string` | `"128Mi"` | no |
| <a name="input_memory_request"></a> [memory\_request](#input\_memory\_request) | Memory request for the node-cache container. | `string` | `"128Mi"` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | The namespace in which node-local-dns will be installed. | `string` | `"kube-system"` | no |
| <a name="input_upstream_cache_ttl"></a> [upstream\_cache\_ttl](#input\_upstream\_cache\_ttl) | Cache TTL in seconds for external (non-cluster) DNS names. | `number` | `30` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_daemonset_name"></a> [daemonset\_name](#output\_daemonset\_name) | Name of the node-local-dns DaemonSet |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace the node-local-dns DaemonSet runs in |
| <a name="output_release_name"></a> [release\_name](#output\_release\_name) | Name of the node-local-dns helm release |
