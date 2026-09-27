# RustFS as an in-cluster, S3-compatible persist backend.
#
# Deployed as a StatefulSet rather than through rustfs/operator: the operator is
# at 0.0.x and rustfs/helm publishes no releases, and a benchmark backend should
# fail in ways attributable to the store rather than to its control plane. The
# operator's Tenant CRD is the natural second deployment mode once it settles.

locals {
  secret_key = var.secret_key != null ? var.secret_key : random_password.secret_key[0].result
  rpc_secret = var.rpc_secret != null ? var.rpc_secret : random_password.rpc_secret[0].result

  namespace = var.create_namespace ? kubernetes_namespace.this[0].metadata[0].name : var.namespace

  labels = {
    "app.kubernetes.io/name"       = "rustfs"
    "app.kubernetes.io/instance"   = var.name
    "app.kubernetes.io/component"  = "object-store"
    "app.kubernetes.io/managed-by" = "terraform"
  }

  headless_service = "${var.name}-headless"

  # RustFS takes MinIO-style ellipsis ranges and erasure-codes across every
  # drive the range expands to. A single pod with a single drive has no range
  # to expand, so it gets the bare path.
  drive_range = var.drives_per_replica > 1 ? "/data{0...${var.drives_per_replica - 1}}" : "/data"

  volumes = (
    var.replicas > 1
    ? "http://${var.name}-{0...${var.replicas - 1}}.${local.headless_service}.${local.namespace}.svc.cluster.local:9000${local.drive_range}"
    : local.drive_range
  )

  endpoint = "http://${var.name}.${local.namespace}.svc.cluster.local:9000"
}

resource "random_password" "secret_key" {
  count = var.secret_key == null ? 1 : 0

  length  = 32
  special = false
}

# Servers authenticate to each other with this when the store spans more than
# one pod. RustFS can derive it from the root credentials, but refuses to when
# those are left at their defaults, so a multi-node store fails to start unless
# it is set. A single-node store never forms an RPC connection and never needs
# it, which is why this only shows up beyond one replica.
resource "random_password" "rpc_secret" {
  count = var.rpc_secret == null ? 1 : 0

  length  = 32
  special = false
}

resource "kubernetes_namespace" "this" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name   = var.namespace
    labels = local.labels
  }
}

resource "kubernetes_secret" "credentials" {
  metadata {
    name      = "${var.name}-credentials"
    namespace = local.namespace
    labels    = local.labels
  }

  data = {
    access_key = var.access_key
    secret_key = local.secret_key
    rpc_secret = local.rpc_secret
  }

  type = "Opaque"
}

# Stable per-pod DNS, which the multi-node volume range above resolves against.
resource "kubernetes_service" "headless" {
  metadata {
    name      = local.headless_service
    namespace = local.namespace
    labels    = local.labels
  }

  spec {
    cluster_ip                  = "None"
    publish_not_ready_addresses = true
    selector                    = local.labels

    port {
      name        = "s3"
      port        = 9000
      target_port = 9000
    }
  }
}

# What clients connect to.
resource "kubernetes_service" "this" {
  metadata {
    name      = var.name
    namespace = local.namespace
    labels    = local.labels
  }

  spec {
    selector = local.labels

    port {
      name        = "s3"
      port        = 9000
      target_port = 9000
    }
  }
}

resource "kubernetes_stateful_set" "this" {
  metadata {
    name      = var.name
    namespace = local.namespace
    labels    = local.labels
  }

  wait_for_rollout = var.wait_for_ready

  spec {
    service_name          = kubernetes_service.headless.metadata[0].name
    replicas              = var.replicas
    pod_management_policy = "Parallel"

    selector {
      match_labels = local.labels
    }

    template {
      metadata {
        labels = local.labels
      }

      spec {
        node_selector = var.node_selector

        # The image runs as a non-root user and chowns /data at build time, but
        # a mounted volume replaces that with a filesystem the provisioner owns.
        # fsGroup makes kubelet hand the volume to the server's group, without
        # which it fails to start with a permission error. Hosts that hand back
        # a world-writable directory hide this, so it only shows on a volume
        # with real ownership.
        security_context {
          fs_group = var.fs_group
        }

        # One server per node. Without this the pods are small enough to pack
        # onto a single node, which puts every erasure-coded copy on one disk
        # and defeats the point of running more than one replica. It also
        # starves the later replicas: a node's volume group only holds so many
        # drives, so the last claims fail to provision rather than moving to a
        # node with room. Requiring one per node is what makes the autoscaler
        # add nodes instead.
        dynamic "affinity" {
          for_each = var.spread_across_nodes && var.replicas > 1 ? [1] : []
          content {
            pod_anti_affinity {
              required_during_scheduling_ignored_during_execution {
                label_selector {
                  match_labels = local.labels
                }
                topology_key = "kubernetes.io/hostname"
              }
            }
          }
        }

        dynamic "toleration" {
          for_each = var.tolerations
          content {
            key      = toleration.value.key
            operator = toleration.value.operator
            value    = toleration.value.value
            effect   = toleration.value.effect
          }
        }

        container {
          name  = "rustfs"
          image = var.image

          env {
            name = "RUSTFS_ACCESS_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.credentials.metadata[0].name
                key  = "access_key"
              }
            }
          }

          env {
            name = "RUSTFS_SECRET_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.credentials.metadata[0].name
                key  = "secret_key"
              }
            }
          }

          # Only consulted when the store spans several pods, but harmless to
          # set for one, so it is not made conditional.
          env {
            name = "RUSTFS_RPC_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.credentials.metadata[0].name
                key  = "rpc_secret"
              }
            }
          }

          env {
            name  = "RUSTFS_ADDRESS"
            value = ":9000"
          }

          env {
            name  = "RUSTFS_VOLUMES"
            value = local.volumes
          }

          port {
            name           = "s3"
            container_port = 9000
          }

          readiness_probe {
            http_get {
              path = "/health/ready"
              port = 9000
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }

          resources {
            requests = var.resources.requests
            limits   = var.resources.limits
          }

          dynamic "volume_mount" {
            for_each = range(var.drives_per_replica)
            content {
              name       = "data-${volume_mount.value}"
              mount_path = "/data${var.drives_per_replica > 1 ? volume_mount.value : ""}"
            }
          }
        }
      }
    }

    dynamic "volume_claim_template" {
      for_each = range(var.drives_per_replica)
      content {
        metadata {
          name   = "data-${volume_claim_template.value}"
          labels = local.labels
        }

        spec {
          access_modes       = ["ReadWriteOnce"]
          storage_class_name = var.storage_class

          resources {
            requests = {
              storage = var.drive_size
            }
          }
        }
      }
    }
  }
}

# RustFS does not create buckets itself, so persist has nothing to write to
# until this runs. `mb` on an existing bucket is an error, so a successful `ls`
# is treated as done, which also makes the Job idempotent across re-applies.
resource "kubernetes_job" "create_bucket" {
  metadata {
    name      = "${var.name}-create-bucket"
    namespace = local.namespace
    labels    = local.labels
  }

  spec {
    backoff_limit = 6

    template {
      metadata {
        labels = local.labels
      }

      spec {
        restart_policy = "OnFailure"

        node_selector = var.node_selector

        dynamic "toleration" {
          for_each = var.tolerations
          content {
            key      = toleration.value.key
            operator = toleration.value.operator
            value    = toleration.value.value
            effect   = toleration.value.effect
          }
        }

        container {
          name  = "awscli"
          image = var.setup_image

          env {
            name = "AWS_ACCESS_KEY_ID"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.credentials.metadata[0].name
                key  = "access_key"
              }
            }
          }

          env {
            name = "AWS_SECRET_ACCESS_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.credentials.metadata[0].name
                key  = "secret_key"
              }
            }
          }

          env {
            name  = "AWS_DEFAULT_REGION"
            value = var.region
          }

          command = ["/bin/sh", "-c"]
          args = [
            <<-EOT
              ep=${local.endpoint}
              until aws --endpoint-url "$ep" s3 mb s3://${var.bucket} ||
                    aws --endpoint-url "$ep" s3 ls s3://${var.bucket}; do
                echo "waiting for rustfs..."; sleep 3
              done
            EOT
          ]
        }
      }
    }
  }

  wait_for_completion = var.wait_for_ready

  timeouts {
    create = "10m"
    update = "10m"
  }

  depends_on = [kubernetes_stateful_set.this]
}
