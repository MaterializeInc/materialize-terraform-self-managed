locals {
  disk_setup_name = coalesce(var.disk_setup_name, "${var.name}-disk-setup")

  node_labels = merge(
    var.node_labels,
    var.swap_enabled ? {
      "materialize.cloud/swap" = "true"
    } : {}
  )

  disk_setup_labels = merge(
    var.node_labels,
    {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "materialize"
      "app"                          = local.disk_setup_name
    }
  )
}

resource "kubectl_manifest" "nodeclass" {
  yaml_body = jsonencode(
    {
      "apiVersion" : "karpenter.azure.com/v1beta1",
      "kind" : "AKSNodeClass",
      "metadata" : {
        "name" : var.name,
      },
      "spec" : {
        # Node Auto Provisioning otherwise puts the OS on an ephemeral disk,
        # taking the local NVMe disks that disk-setup uses for swap.
        "osDiskType" : "Managed",
        "osDiskSizeGB" : var.os_disk_size_gb,
        "tags" : var.tags,
      },
    }
  )
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
              "labels" : local.node_labels,
            },
            "spec" : merge(
              {
                "expireAfter" : var.expire_after,
                "nodeClassRef" : {
                  "group" : "karpenter.azure.com",
                  "kind" : "AKSNodeClass",
                  "name" : var.name,
                },
                "requirements" : concat(
                  [
                    {
                      "key" : "node.kubernetes.io/instance-type",
                      "operator" : "In",
                      "values" : var.vm_sizes,
                    },
                    {
                      "key" : "karpenter.sh/capacity-type",
                      "operator" : "In",
                      "values" : ["on-demand"],
                    },
                  ],
                  var.zones != null ? [
                    {
                      "key" : "topology.kubernetes.io/zone",
                      "operator" : "In",
                      "values" : [for zone in var.zones : "${var.location}-${zone}"],
                    },
                  ] : [],
                ),
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
    kubectl_manifest.nodeclass,
  ]
}

resource "kubernetes_namespace" "disk_setup" {
  count = var.swap_enabled ? 1 : 0

  metadata {
    name   = local.disk_setup_name
    labels = local.disk_setup_labels
  }
}

resource "kubernetes_daemonset" "disk_setup" {
  count = var.swap_enabled ? 1 : 0

  metadata {
    name      = local.disk_setup_name
    namespace = kubernetes_namespace.disk_setup[0].metadata[0].name
    labels    = local.disk_setup_labels
  }

  spec {
    selector {
      match_labels = {
        app = local.disk_setup_name
      }
    }

    template {
      metadata {
        labels = local.disk_setup_labels
      }

      spec {
        security_context {
          run_as_non_root = false
          run_as_user     = 0
          fs_group        = 0
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        affinity {
          node_affinity {
            required_during_scheduling_ignored_during_execution {
              node_selector_term {
                match_expressions {
                  key      = "karpenter.sh/nodepool"
                  operator = "In"
                  values   = [var.name]
                }
              }
            }
          }
        }

        dynamic "toleration" {
          for_each = var.node_taints
          content {
            key      = toleration.value.key
            operator = "Exists"
            effect   = toleration.value.effect
          }
        }

        host_network = true
        host_pid     = true

        init_container {
          name    = local.disk_setup_name
          image   = var.disk_setup_image
          command = ["ephemeral-storage-setup"]
          args = [
            "swap",
            "--cloud-provider",
            "azure",
            "--hack-restart-kubelet-enable-swap",
            "--apply-sysctls",
          ]
          resources {
            limits = {
              memory = var.disk_setup_container_resource_config.memory_limit
            }
            requests = {
              memory = var.disk_setup_container_resource_config.memory_request
              cpu    = var.disk_setup_container_resource_config.cpu_request
            }
          }

          security_context {
            privileged  = true
            run_as_user = 0
          }

          env {
            name = "NODE_NAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }

          volume_mount {
            name       = "dev"
            mount_path = "/dev"
          }

          volume_mount {
            name       = "host-root"
            mount_path = "/host"
          }
        }

        container {
          name    = "pause"
          image   = var.disk_setup_image
          command = ["ephemeral-storage-setup"]
          args    = ["sleep"]
          resources {
            limits = {
              memory = var.pause_container_resource_config.memory_limit
            }
            requests = {
              memory = var.pause_container_resource_config.memory_request
              cpu    = var.pause_container_resource_config.cpu_request
            }
          }
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            run_as_non_root            = true
            run_as_user                = 65534
          }
        }

        volume {
          name = "dev"
          host_path {
            path = "/dev"
          }
        }

        volume {
          name = "host-root"
          host_path {
            path = "/"
          }
        }

        service_account_name = kubernetes_service_account.disk_setup[0].metadata[0].name
      }
    }
  }
}

resource "kubernetes_service_account" "disk_setup" {
  count = var.swap_enabled ? 1 : 0

  metadata {
    name      = local.disk_setup_name
    namespace = kubernetes_namespace.disk_setup[0].metadata[0].name
  }
}

resource "kubernetes_cluster_role" "disk_setup" {
  count = var.swap_enabled ? 1 : 0

  metadata {
    name = local.disk_setup_name
  }
  rule {
    api_groups = [""]
    resources  = ["nodes"]
    verbs      = ["get", "patch", "update"]
  }
}

resource "kubernetes_cluster_role_binding" "disk_setup" {
  count = var.swap_enabled ? 1 : 0

  metadata {
    name = local.disk_setup_name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.disk_setup[0].metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.disk_setup[0].metadata[0].name
    namespace = kubernetes_namespace.disk_setup[0].metadata[0].name
  }
}
