# Terraform doesn't know about any EC2 instances spawned by
# Karpenter. To avoid leaking them, we delete the associated
# nodeclaims after destroying the nodepool.
#
# The nodeclaims have a finalizer that won't let them be
# deleted until the associated EC2 instance is deleted.
resource "terraform_data" "destroyer" {
  input = {
    NODEPOOL_NAME   = var.name
    KUBECONFIG_DATA = var.kubeconfig_data
  }

  provisioner "local-exec" {
    when = destroy

    command     = "sh '${path.module}/scripts/delete-nodeclaims.sh'"
    environment = self.input
  }
}

resource "kubectl_manifest" "nodepool" {
  yaml_body = jsonencode(
    {
      "apiVersion" : "karpenter.sh/v1",
      "kind" : "NodePool",
      "metadata" : {
        "name" : var.name,
      },
      "spec" : merge(
        {
          "disruption" : var.disruption,
          "template" : {
            "metadata" : {
              "labels" : var.node_labels,
            },
            "spec" : merge(
              {
                "expireAfter" : var.expire_after,
                "nodeClassRef" : {
                  "group" : "karpenter.k8s.aws",
                  "kind" : "EC2NodeClass",
                  "name" : var.nodeclass_name,
                },
                "requirements" : [
                  {
                    "key" : "node.kubernetes.io/instance-type",
                    "operator" : "In",
                    "values" : var.instance_types,
                  },
                  # TODO zone?
                  {
                    "key" : "karpenter.sh/capacity-type",
                    "operator" : "In",
                    "values" : ["on-demand"],
                  },
                ],
                "taints" : var.node_taints,
              },
              var.termination_grace_period != null ? {
                "terminationGracePeriod" : var.termination_grace_period,
              } : {},
            ),
          },
        },
        var.limits != null ? {
          "limits" : var.limits,
        } : {},
      ),
    }
  )

  depends_on = [
    terraform_data.destroyer,
  ]
}
