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

    command     = <<-EOF
      set -euo pipefail

      if [ -z "$${KUBECONFIG_DATA}" ]; then
        echo "Error: KUBECONFIG_DATA is empty"
        exit 1
      fi

      kubeconfig_file=$(mktemp)
      echo "$${KUBECONFIG_DATA}" > "$${kubeconfig_file}"
      trap "rm -f $${kubeconfig_file}" EXIT

      nodeclaims=$(kubectl --kubeconfig "$${kubeconfig_file}" get nodeclaims -l "karpenter.sh/nodepool=$${NODEPOOL_NAME}" -o name)
      if [ -n "$${nodeclaims}" ]; then
        echo "$${nodeclaims}" | xargs kubectl --kubeconfig "$${kubeconfig_file}" delete --wait=true
      fi
    EOF
    interpreter = ["/usr/bin/env", "bash", "-c"]

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
      "spec" : {
        "disruption" : var.disruption,
        "template" : {
          "metadata" : {
            "labels" : var.node_labels,
          },
          "spec" : {
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
            "terminationGracePeriod" : "60s",
          },
        },
      },
    }
  )

  depends_on = [
    terraform_data.destroyer,
  ]
}
