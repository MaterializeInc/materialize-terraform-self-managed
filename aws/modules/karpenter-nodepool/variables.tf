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

variable "termination_grace_period" {
  description = <<-EOT
    Maximum time Karpenter will wait for pods to drain before forcefully
    terminating a node, e.g. "300s". When set, Karpenter will disrupt nodes
    (e.g. on drift after an instance type change) even if they run pods with
    the karpenter.sh/do-not-disrupt annotation or blocking PDBs; those pods
    are only protected until the node's termination deadline, after which
    they are evicted. Leave null so that do-not-disrupt pods (such as
    Materialize instance pods) block disruption until they are removed by a
    Materialize rollout.
  EOT
  type        = string
  default     = null
}

variable "limits" {
  description = <<-EOT
    Resource limits for the NodePool, e.g. { cpu = "1000" }. Karpenter stops
    provisioning new nodes from this pool once the total resources of its
    nodes reach these limits; existing nodes are unaffected. Setting
    { cpu = "0" } prevents the pool from provisioning any new nodes, which
    is useful when migrating workloads to another pool. Limits are not part
    of the NodePool template, so changing them does not drift-replace
    existing nodes.
  EOT
  type        = map(string)
  default     = null
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
