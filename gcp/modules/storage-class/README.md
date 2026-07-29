# GCP Storage Class Module

This module creates a Kubernetes StorageClass optimized for GCP Persistent Disks in multi-zone GKE clusters.

## Why This Module?

GCP Persistent Disks are **zonal resources** - they exist in a single zone and can only be attached to nodes in that same zone. In multi-zone GKE clusters, this creates a challenge: if you create a PersistentVolume before knowing where the pod will run, the pod might get scheduled to a different zone than where its storage lives, causing the pod to fail.

This module creates a StorageClass with `volumeBindingMode: WaitForFirstConsumer`, which solves this problem by delaying volume creation until a pod is scheduled. The CSI driver then creates the Persistent Disk in the same zone as the scheduled node.

## GKE Default Storage Classes

GKE automatically creates several storage classes:

| Name | Disk Type | Binding Mode | Notes |
|------|-----------|--------------|-------|
| `standard` | pd-standard (HDD) | Immediate | Legacy, not recommended for multi-zone |
| `standard-rwo` | pd-balanced | WaitForFirstConsumer | **Recommended default** |
| `premium-rwo` | pd-ssd | WaitForFirstConsumer | Higher performance |

The `standard-rwo` class already uses `WaitForFirstConsumer` and works well for most use cases. Use this module when you need:
- A custom storage class name
- Specific disk type configuration
- Volume expansion settings
- Regional Persistent Disk replication

## Usage

### Using GKE Default (Recommended for Most Users)

If you're happy with `standard-rwo`, you don't need this module:

```hcl
locals {
  storage_class = "standard-rwo"  # GKE default, already has WaitForFirstConsumer
}
```

### Creating a Custom SSD Storage Class

```hcl
module "storage_class" {
  source = "../../modules/storage-class"

  storage_class_name = "pd-ssd"
  disk_type          = "pd-ssd"
  set_as_default     = false
}
```

### Creating a Regional Persistent Disk Storage Class

For higher availability, you can use regional PDs that replicate across two zones:

```hcl
module "storage_class" {
  source = "../../modules/storage-class"

  storage_class_name = "regional-pd-ssd"
  disk_type          = "pd-ssd"
  replication_type   = "regional-pd"
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| kubernetes | >= 2.10.0, < 2.39.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| create_storage_class | Whether to create the storage class | `bool` | `true` | no |
| storage_class_name | Name of the Kubernetes StorageClass | `string` | `"pd-ssd"` | no |
| disk_type | Type of GCP Persistent Disk (pd-standard, pd-ssd, pd-balanced, pd-extreme) | `string` | `"pd-ssd"` | no |
| reclaim_policy | Reclaim policy (Delete, Retain) | `string` | `"Delete"` | no |
| allow_volume_expansion | Allow volume expansion after creation | `bool` | `true` | no |
| set_as_default | Set as cluster default storage class | `bool` | `false` | no |
| replication_type | Disk replication (none, regional-pd) | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| storage_class_name | Name of the storage class |

## Multi-Zone Considerations

### Zonal vs Regional Persistent Disks

- **Zonal PDs** (default): Lower cost, data in one zone. If that zone fails, data is inaccessible until the zone recovers.
- **Regional PDs** (`replication_type = "regional-pd"`): Higher cost, data replicated across two zones. Provides zone-level fault tolerance.

### Pod Scheduling with Zonal PDs

With `WaitForFirstConsumer`:
1. Pod is created and needs a PVC
2. Kubernetes schedules the pod to a node (e.g., in `us-central1-a`)
3. The CSI driver creates the PD in `us-central1-a`
4. Pod starts successfully

If the pod is rescheduled (e.g., node failure), it will only be scheduled to nodes in `us-central1-a` where its volume exists.

### StatefulSets

StatefulSets work well with this pattern because each replica gets its own PVC, and the `WaitForFirstConsumer` binding ensures each volume is created in the zone where its pod runs.
