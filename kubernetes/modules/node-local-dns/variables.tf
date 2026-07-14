variable "namespace" {
  description = "The namespace in which node-local-dns will be installed."
  type        = string
  nullable    = false
  default     = "kube-system"
}

variable "chart_version" {
  description = "Version of the node-local-dns helm chart to install."
  type        = string
  nullable    = false
  default     = "2.1.0"
}

variable "install_timeout" {
  description = "Timeout for installing the node-local-dns helm chart, in seconds."
  type        = number
  nullable    = false
  default     = 300
}

variable "dns_server" {
  description = "ClusterIP of the kube-dns service. node-local-dns binds this IP on a local dummy interface to intercept pod DNS traffic (iptables mode). On EKS this is the .10 address of the cluster service CIDR."
  type        = string
  nullable    = false
  validation {
    condition     = can(cidrnetmask("${var.dns_server}/32"))
    error_message = "dns_server must be a valid IPv4 address"
  }
}

variable "local_dns_ip" {
  description = "Link-local IP that node-local-dns additionally binds. Only used as --cluster-dns in IPVS mode; must not collide with anything."
  type        = string
  nullable    = false
  default     = "169.254.20.25"
}

variable "cluster_domain" {
  description = "Internal Kubernetes DNS domain."
  type        = string
  nullable    = false
  default     = "cluster.local"
}

variable "cluster_cache_ttl" {
  description = "Cache TTL in seconds for the cluster DNS zones (cluster domain and reverse zones). Kept at 1s to avoid stale pod IPs during Materialize rollouts, matching the TTL-0 intent of the custom CoreDNS deployment while still absorbing query floods."
  type        = number
  nullable    = false
  default     = 1
}

variable "upstream_cache_ttl" {
  description = "Cache TTL in seconds for external (non-cluster) DNS names."
  type        = number
  nullable    = false
  default     = 30
}

variable "cpu_request" {
  description = "CPU request for the node-cache container."
  type        = string
  nullable    = false
  default     = "25m"
}

variable "memory_request" {
  description = "Memory request for the node-cache container."
  type        = string
  nullable    = false
  default     = "128Mi"
}

variable "memory_limit" {
  description = "Memory limit for the node-cache container."
  type        = string
  nullable    = false
  default     = "128Mi"
}
