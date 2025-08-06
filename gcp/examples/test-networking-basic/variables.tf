variable "project_id" {
  description = "The ID of the project where resources will be created"
  type        = string
}

variable "region" {
  description = "The region where resources will be created"
  type        = string
  default     = "us-central1"
}

variable "prefix" {
  description = "Prefix to be used for resource names"
  type        = string
}

variable "subnets" {
  description = "Subnets to be created"
  type = list(object({
    name           = string
    cidr           = string
    region         = string
    private_access = optional(bool, true)
    secondary_ranges = optional(list(object({
      range_name    = string
      ip_cidr_range = string
    })), [])
  }))
  default = [{
    name           = "default-private-subnet"
    cidr           = "10.100.0.0/20"
    region         = "us-central1"
    private_access = true
    secondary_ranges = [
      {
        range_name    = "pods"
        ip_cidr_range = "10.104.0.0/14"
      },
      {
        range_name    = "services"
        ip_cidr_range = "10.108.0.0/20"
      }
    ]
  }]
}
