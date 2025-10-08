variable "name" {
  description = "Name of the NodePool."
  type        = string
  nullable    = false
}

variable "nodeclass_name" {
  description = "Name of the EC2NodeClass."
  type        = string
  nullable    = false
}

variable "instance_types" {
  description = "List of instance types to support."
  type        = list(string)
  nullable    = false
}

variable "node_labels" {
  description = "Labels to apply to created Kubernetes nodes."
  type        = map(string)
  nullable    = false
}

variable "kubeconfig_data" {
  description = "Contents of the kubeconfig used for cleanup of EC2 instances on destroy."
  type        = string
  nullable    = false
}

variable "disruption" {
  description = "Configuration for node disruption."
  type        = any
  default = {
    "budgets" : [
      {
        "nodes" : "10%",
      },
    ],
    "consolidateAfter" : "60s",
    "consolidationPolicy" : "WhenEmpty",
  }
}

variable "expire_after" {
  description = "Time after which the node will expire."
  type        = string
  default     = "Never"
}

variable "node_taints" {
  description = "Taints to apply to the node."
  type = list(object({
    key    = string
    value  = string
    effect = string
  }))
  default = null
}
