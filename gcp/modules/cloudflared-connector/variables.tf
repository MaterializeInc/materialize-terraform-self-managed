variable "project_id" {
  description = "GCP project to run the connectors in."
  type        = string
}

variable "region" {
  description = "Region for the connector instance group."
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "network" {
  description = "Name or self link of the VPC network the connectors join. It needs outbound internet access (for example Cloud NAT)."
  type        = string
}

variable "subnetwork" {
  description = "Name or self link of the subnetwork the connectors join. It must be able to reach the Materialize load balancers."
  type        = string
}

variable "tunnel_token" {
  description = "Cloudflare tunnel token the connectors run with."
  type        = string
  sensitive   = true
}

variable "replicas" {
  description = "Number of connector VMs. Cloudflare balances across them; 2 or more survives a VM or zone loss."
  type        = number
  default     = 2
}

variable "machine_type" {
  description = "Machine type for connector VMs."
  type        = string
  default     = "e2-small"
}

variable "cloudflared_image" {
  description = "cloudflared container image."
  type        = string
  default     = "cloudflare/cloudflared:2026.11.0"
}

variable "labels" {
  description = "Labels applied to connector resources."
  type        = map(string)
  default     = {}
}
