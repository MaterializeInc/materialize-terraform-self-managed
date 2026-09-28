# Ceph as an in-cluster, S3-compatible persist backend, deployed by Rook.
#
# The Ceph CRDs only exist once the operator chart is installed, so the custom
# resources go through kubectl_manifest rather than kubernetes_manifest, which
# would need the types registered at plan time. This matches how the karpenter
# and monitoring modules handle the same problem.

locals {
  namespace = var.create_namespace ? kubernetes_namespace.this[0].metadata[0].name : var.namespace

  labels = {
    "app.kubernetes.io/name"       = "ceph"
    "app.kubernetes.io/instance"   = var.name
    "app.kubernetes.io/component"  = "object-store"
    "app.kubernetes.io/managed-by" = "terraform"
  }

  # Rook names the generated credentials secret after the store and user.
  user_secret_name = "rook-ceph-object-user-${var.name}-${var.object_store_user}"

  # The in-cluster service Rook creates for the gateway.
  endpoint = "http://rook-ceph-rgw-${var.name}.${local.namespace}.svc.cluster.local"

  # The trailing newline is required, not cosmetic: Ceph's ini parser expects a
  # line terminator at end of file and rejects the whole config without one,
  # which leaves every daemon failing to start with a parse error naming the
  # position one past the last character.
  ceph_config = "${join("\n", compact([
    "[global]",
    "rgw_max_chunk_size = ${var.rgw_chunk_size_bytes}",
    "rgw_obj_stripe_size = ${var.rgw_chunk_size_bytes}",
    var.osd_memory_target_bytes != null ? "osd_memory_target = ${var.osd_memory_target_bytes}" : null,
    var.replica_size == 1 ? "mon_allow_pool_size_one = true" : null,
    var.extra_ceph_config,
  ]))}\n"

  # Two ways to give Ceph disks. `storageClassDeviceSets` asks the scheduler for
  # PersistentVolumes and makes one OSD per volume, which is how Rook runs in a
  # cloud and the only option once `ephemeral-storage-setup lvm` has claimed the
  # raw NVMe into a volume group. Naming devices directly is the bare-metal
  # path, kept for clusters that hand Rook whole disks.
  #
  # Built by dropping nulls rather than by a conditional: the two shapes have
  # no attributes in common, and terraform requires both results of a `? :` to
  # unify into one type.
  storage = {
    for key, value in {
      storageClassDeviceSets = var.osd_storage_class == null ? null : [
        {
          name                = "${var.name}-osd"
          count               = var.osd_count
          portable            = false
          tuneFastDeviceClass = true
          encrypted           = false
          placement           = local.osd_placement
          preparePlacement    = local.osd_prepare_placement
          volumeClaimTemplates = [
            {
              metadata = {
                name = "data"
              }
              spec = {
                accessModes = ["ReadWriteOnce"]
                # Ceph writes to the block device itself rather than a
                # filesystem on it, which is where BlueStore is fastest.
                volumeMode       = "Block"
                storageClassName = var.osd_storage_class
                resources = {
                  requests = {
                    storage = var.osd_size
                  }
                }
              }
            }
          ]
        }
      ]
      useAllNodes   = var.osd_storage_class == null ? true : null
      useAllDevices = var.osd_storage_class == null ? var.use_all_devices : null
      deviceFilter  = var.osd_storage_class == null ? var.device_filter : null
    } : key => value if value != null
  }

  placement = {
    all = merge(
      length(var.node_selector) > 0 ? { nodeAffinity = {
        requiredDuringSchedulingIgnoredDuringExecution = {
          nodeSelectorTerms = [{
            matchExpressions = [
              for k, v in var.node_selector : {
                key      = k
                operator = "In"
                values   = [v]
              }
            ]
          }]
        }
      } } : {},
      length(var.tolerations) > 0 ? { tolerations = [
        for t in var.tolerations : merge(
          {
            key      = t.key
            operator = t.operator
            effect   = t.effect
          },
          t.value != null ? { value = t.value } : {},
        )
      ] } : {},
    )
  }

  # A node-local volume binds to whichever node its OSD's prepare pod first
  # schedules on, and nothing else stops two of them choosing the same node.
  # Two OSDs on one host leave a `host` failure domain a host short, and
  # replicas that need distinct hosts sit undersized. The hard constraint
  # therefore goes on the prepare pods. The OSD pods only get a soft one:
  # their volume already pins them, and a hard constraint there could leave
  # one unschedulable forever. OSD pods are counted too, because a prepare pod
  # that has completed no longer counts for spreading.
  osd_spread = {
    maxSkew     = 1
    topologyKey = "kubernetes.io/hostname"
    labelSelector = {
      matchExpressions = [{
        key      = "app"
        operator = "In"
        values   = ["rook-ceph-osd", "rook-ceph-osd-prepare"]
      }]
    }
  }

  osd_prepare_placement = merge(local.placement.all, {
    topologySpreadConstraints = [merge(local.osd_spread, { whenUnsatisfiable = "DoNotSchedule" })]
  })

  osd_placement = merge(local.placement.all, {
    topologySpreadConstraints = [merge(local.osd_spread, { whenUnsatisfiable = "ScheduleAnyway" })]
  })
}

resource "kubernetes_namespace" "this" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name   = var.namespace
    labels = local.labels
  }
}

# Daemons read this at start-up, so it has to exist before the cluster does.
# The two RGW sizes are the reason this module sets any Ceph config at all:
# both default to 4 MiB, which fragments every persist blob above that.
resource "kubernetes_config_map" "ceph_config_override" {
  metadata {
    name      = "rook-config-override"
    namespace = local.namespace
    labels    = local.labels
  }

  data = {
    config = local.ceph_config
  }
}

resource "helm_release" "rook_operator" {
  name       = "rook-ceph"
  namespace  = local.namespace
  repository = "https://charts.rook.io/release"
  chart      = "rook-ceph"
  version    = var.operator_chart_version
  timeout    = var.install_timeout

  # Persist reaches Ceph through the RGW's S3 API and never mounts a Ceph
  # volume, so the CSI stack is dead weight: a controller plus plugin pods on
  # every node in the cluster, each holding a pod IP and each able to hold up
  # the release, since Helm waits for all of them to be ready.
  set {
    name  = "csi.installCsiOperator"
    value = var.install_csi
  }

  dynamic "set" {
    for_each = var.node_selector
    content {
      name = "nodeSelector.${replace(set.key, ".", "\\.")}"
      # Helm infers types, so a label value of "true" or a bare number would
      # reach the API server as a bool or an int. Node selector values are
      # strings, and the request is rejected outright if they are not.
      type  = "string"
      value = set.value
    }
  }

  dynamic "set" {
    for_each = length(var.tolerations) > 0 ? range(length(var.tolerations)) : []
    content {
      name  = "tolerations[${set.value}].key"
      value = var.tolerations[set.value].key
    }
  }

  dynamic "set" {
    for_each = length(var.tolerations) > 0 ? range(length(var.tolerations)) : []
    content {
      name  = "tolerations[${set.value}].operator"
      value = var.tolerations[set.value].operator
    }
  }

  dynamic "set" {
    for_each = length(var.tolerations) > 0 ? [
      for i, toleration in var.tolerations : i
      if toleration.value != null
    ] : []
    content {
      name  = "tolerations[${set.value}].value"
      value = var.tolerations[set.value].value
    }
  }

  dynamic "set" {
    for_each = length(var.tolerations) > 0 ? range(length(var.tolerations)) : []
    content {
      name  = "tolerations[${set.value}].effect"
      value = var.tolerations[set.value].effect
    }
  }

  depends_on = [
    kubernetes_namespace.this,
    kubernetes_config_map.ceph_config_override,
  ]
}

resource "kubectl_manifest" "ceph_cluster" {
  yaml_body = yamlencode({
    apiVersion = "ceph.rook.io/v1"
    kind       = "CephCluster"
    metadata = {
      name      = var.name
      namespace = local.namespace
      labels    = local.labels
    }
    # NOTE: no `cleanupPolicy` here, however much it looks like the field that
    # erases `dataDirHostPath`. Rook reads it as "this cluster is being torn
    # down" and stops reconciling: a cluster created with it set never
    # orchestrates at all, and the only sign is one operator log line,
    # `skipping orchestration for cluster object ... because its cleanup policy
    # is set`, while the CR sits with an empty phase. It is a patch applied to
    # a live cluster immediately before deleting it.
    spec = {
      dataDirHostPath = var.data_dir_host_path
      cephVersion = {
        image = var.ceph_image
      }
      mon = {
        count                = var.mon_count
        allowMultiplePerNode = var.mon_count == 1
      }
      mgr = {
        count                = 1
        allowMultiplePerNode = var.mon_count == 1
      }
      dashboard = {
        enabled = false
      }
      crashCollector = {
        disable = true
      }
      storage   = local.storage
      placement = local.placement
    }
  })

  # NOTE: `wait` only ever affects deletion. It holds a delete until Rook's
  # finalizers finish, which is what tears the user, the store and the cluster
  # down in dependency order. Readiness on create is `wait_for`, and without it
  # Terraform moves on the moment the API server accepts the manifest: the
  # user's credentials secret is then read before Rook has written it, and the
  # first apply fails indexing a null secret. Each of these resources reports
  # `status.phase: Ready` once reconciled.
  wait = true

  dynamic "wait_for" {
    for_each = var.wait_for_ready ? [1] : []
    content {
      field {
        key   = "status.phase"
        value = "Ready"
      }
    }
  }

  # A cluster can outlast the default ten minutes when a mon is left in
  # scheduler backoff after its canary.
  timeouts {
    create = "30m"
  }

  depends_on = [helm_release.rook_operator]
}

resource "kubectl_manifest" "object_store" {
  yaml_body = yamlencode({
    apiVersion = "ceph.rook.io/v1"
    kind       = "CephObjectStore"
    metadata = {
      name      = var.name
      namespace = local.namespace
      labels    = local.labels
    }
    spec = {
      metadataPool = {
        failureDomain = var.failure_domain
        replicated = {
          size                   = var.replica_size
          requireSafeReplicaSize = var.replica_size > 1
        }
      }
      dataPool = {
        failureDomain = var.failure_domain
        replicated = {
          size                   = var.replica_size
          requireSafeReplicaSize = var.replica_size > 1
        }
      }
      preservePoolsOnDelete = false
      gateway = {
        port      = 80
        instances = var.gateway_instances
        # NOTE: `.all`, not the map itself. A CephCluster's placement is keyed
        # by daemon type and the gateway's is a bare placement, and Rook
        # ignores the unknown `all` key without complaint, which leaves the
        # gateway free to land on any node. The gateway is the request path,
        # so on a general-purpose node it caps the store at that node's
        # network allowance.
        placement = local.placement.all

        # Beast leaves Nagle's algorithm on by default. A GET response goes
        # out as headers then body, so the body waits on the client's delayed
        # ACK: every read paid a flat 50 ms, capping 4 KiB reads at 637 ops/s
        # against 23,160 with this set, and each gateway at about 590 MiB/s.
        # PUT and DELETE answer with headers alone and never showed it.
        #
        # Rook passes its own `--rgw-frontends` first and this one after it,
        # and the later flag wins, so it has to restate the whole value. 8080
        # is Rook's internal container port behind the service's `port`.
        rgwCommandFlags = {
          rgw_frontends = "beast port=8080 tcp_nodelay=1"
        }
      }
    }
  })

  wait = true

  dynamic "wait_for" {
    for_each = var.wait_for_ready ? [1] : []
    content {
      field {
        key   = "status.phase"
        value = "Ready"
      }
    }
  }

  timeouts {
    create = "30m"
  }

  depends_on = [kubectl_manifest.ceph_cluster]
}

resource "kubectl_manifest" "object_store_user" {
  yaml_body = yamlencode({
    apiVersion = "ceph.rook.io/v1"
    kind       = "CephObjectStoreUser"
    metadata = {
      name      = var.object_store_user
      namespace = local.namespace
      labels    = local.labels
    }
    spec = {
      store       = var.name
      displayName = "Materialize persist"
    }
  })

  wait = true

  dynamic "wait_for" {
    for_each = var.wait_for_ready ? [1] : []
    content {
      field {
        key   = "status.phase"
        value = "Ready"
      }
    }
  }

  timeouts {
    create = "30m"
  }

  depends_on = [kubectl_manifest.object_store]
}

# Rook mints the S3 credentials and writes them here, so they are only readable
# after the user resource has been reconciled.
data "kubernetes_secret" "object_store_user" {
  metadata {
    name      = local.user_secret_name
    namespace = local.namespace
  }

  depends_on = [kubectl_manifest.object_store_user]
}

# RGW does not create buckets itself. `mb` on an existing bucket is an error,
# so a successful `ls` is treated as done, which keeps the Job idempotent.
resource "kubernetes_job" "create_bucket" {
  metadata {
    name      = "${var.name}-create-bucket"
    namespace = local.namespace
    labels    = local.labels
  }

  spec {
    backoff_limit = 10

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
                name = local.user_secret_name
                key  = "AccessKey"
              }
            }
          }

          env {
            name = "AWS_SECRET_ACCESS_KEY"
            value_from {
              secret_key_ref {
                name = local.user_secret_name
                key  = "SecretKey"
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
                echo "waiting for the ceph gateway..."; sleep 5
              done
            EOT
          ]
        }
      }
    }
  }

  wait_for_completion = var.wait_for_ready

  timeouts {
    create = "20m"
    update = "20m"
  }

  depends_on = [data.kubernetes_secret.object_store_user]
}
