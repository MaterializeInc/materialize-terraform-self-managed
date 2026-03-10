variable "hosted_zone_id" {
  description = "The Route53 hosted zone ID."
  type        = string
  nullable    = false
}

variable "nlb_dns_name" {
  description = "The DNS name of the NLB."
  type        = string
  nullable    = false
}

variable "nlb_zone_id" {
  description = "The hosted zone ID of the NLB (for ALIAS records)."
  type        = string
  nullable    = false
}

variable "balancerd_domain_name" {
  description = "The domain name for balancerd."
  type        = string
  nullable    = false
}

variable "console_domain_name" {
  description = "The domain name for the console."
  type        = string
  nullable    = false
}
