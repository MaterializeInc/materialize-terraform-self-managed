locals {
  # Map GCP taint effects to Kubernetes toleration effects
  taint_effect_map = {
    "NO_SCHEDULE"        = "NoSchedule"
    "NO_EXECUTE"         = "NoExecute"
    "PREFER_NO_SCHEDULE" = "PreferNoSchedule"
  }

  # disk-setup removes this taint once swap is configured.
  swap_taints = var.swap_enabled ? [
    {
      key    = "startup-taint.cluster-autoscaler.kubernetes.io/disk-unconfigured"
      value  = "true"
      effect = "NO_SCHEDULE"
    }
  ] : []

  node_taints = concat(var.node_taints, local.swap_taints)

  node_labels = merge(
    var.labels,
    var.swap_enabled ? {
      "materialize.cloud/swap" = "true"
    } : {}
  )

  disk_setup_name = coalesce(var.disk_setup_name, "${var.prefix}-disk-setup")

  disk_setup_labels = merge(
    var.labels,
    {
      "app" = local.disk_setup_name
    }
  )
}

resource "google_container_node_pool" "primary_nodes" {
  # google-beta is required for upgrade_settings.blue_green_settings.autoscaled_rollout_policy.
  provider = google-beta

  name     = "${var.prefix}-nodepool"
  location = var.region
  cluster  = var.cluster_name
  project  = var.project_id

  # Zones where nodes in this pool are created. When null, inherits from cluster.
  node_locations = var.node_locations

  autoscaling {
    min_node_count = var.min_nodes
    max_node_count = var.max_nodes
  }

  # GKE auto-upgrades can only be delayed, not disabled. Autoscaled blue-green
  # cordons the old nodes and waits up to wait_for_drain_duration before draining,
  # which gives orchestratord time to roll instances onto the new pool (see the
  # operator module's enable_node_upgrade_rollout_trigger). Needs GKE 1.34.0-gke.2201000+.
  upgrade_settings {
    strategy = "BLUE_GREEN"
    blue_green_settings {
      autoscaled_rollout_policy {
        wait_for_drain_duration = var.upgrade_wait_for_drain_duration
      }
      node_pool_soak_duration = var.upgrade_node_pool_soak_duration
    }
  }

  network_config {
    enable_private_nodes = var.enable_private_nodes
  }

  node_config {
    machine_type = var.machine_type
    disk_size_gb = var.disk_size_gb
    disk_type    = var.disk_type

    labels = local.node_labels

    dynamic "taint" {
      for_each = local.node_taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }

    service_account = var.service_account_email

    oauth_scopes = var.oauth_scopes

    local_nvme_ssd_block_config {
      local_ssd_count = var.local_ssd_count
    }

    workload_metadata_config {
      mode = var.workload_metadata_mode
    }

    linux_node_config {
      sysctls = {
        "vm.swappiness"             = "100",
        "vm.min_free_kbytes"        = "1048576",
        "vm.watermark_scale_factor" = "100",
      }
    }
  }

  lifecycle {
    create_before_destroy = true
    prevent_destroy       = false
  }
}


resource "kubernetes_namespace" "disk_setup" {
  count = var.swap_enabled ? 1 : 0

  metadata {
    name   = local.disk_setup_name
    labels = local.disk_setup_labels
  }

  depends_on = [
    google_container_node_pool.primary_nodes
  ]
}

resource "kubernetes_daemonset" "disk_setup" {
  count = var.swap_enabled ? 1 : 0
  depends_on = [
    kubernetes_namespace.disk_setup
  ]

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
                  key      = "materialize.cloud/swap"
                  operator = "In"
                  values   = ["true"]
                }
                # Only this pool, so several swap pools (e.g. during a machine
                # type migration) each run their own daemonset.
                match_expressions {
                  key      = "cloud.google.com/gke-nodepool"
                  operator = "In"
                  values   = [google_container_node_pool.primary_nodes.name]
                }
              }
            }
          }
        }

        # Tolerate the pool's taints, including the swap taint.
        dynamic "toleration" {
          for_each = local.node_taints
          content {
            key      = toleration.value.key
            operator = "Exists"
            effect   = lookup(local.taint_effect_map, toleration.value.effect, toleration.value.effect)
          }
        }

        # GKE taints Arm nodes; the image is multi-arch.
        toleration {
          key      = "kubernetes.io/arch"
          operator = "Equal"
          value    = "arm64"
          effect   = "NoSchedule"
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
            "gcp",
            "--taint-key",
            local.swap_taints[0].key,
            "--remove-taint",
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
  depends_on = [
    kubernetes_namespace.disk_setup
  ]
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
