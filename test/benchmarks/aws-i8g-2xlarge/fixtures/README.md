# Fixtures for reproducing the comparison

The harness injects one object store per run, which is right for a persist
backend and wrong for a comparison: two stores on one cluster is what removes
the hardware from the result. These are what the AWS run used to get there.

## `second-store-ceph.tf.example`

Copy into a run directory as `ceph_bench.tf` to add Ceph alongside whichever
store `--persist-backend` injected. It brings its own storage node pool, so
the two stores do not share disks, and takes `install_csi_driver = false`
because the first pool already installed the cluster-scoped LVM driver.

Benchmark it by passing its outputs explicitly, since the `object_store_*`
outputs describe the injected store:

```
terraform-tests benchmark --test-run <run> \
  --blob-uri "$(terraform output -raw ceph_persist_backend_url)" \
  --namespace "$(terraform output -raw ceph_namespace)" ...
```

## `warm-ceph-pool.yaml`

Apply before Ceph, and wait for all four pods.

Rook pins each daemon to a node by hostname affinity, and Karpenter will not
provision a node for a pod that already names one, so a pool that scales on
demand deadlocks: the daemons wait for nodes that are waiting for the daemons.
This holds one pod per node with nothing but a pause container, so the nodes
exist before Ceph asks for them.

## Replacing a Ceph cluster

Rebuilding a cluster on nodes that outlive it has several traps:

* A `CephCluster` will not finish deleting while a `CephObjectStore` or
  `CephObjectStoreUser` still exists. Delete the dependents first; the
  operator log names them.
* The `rook-ceph-mon` secret and `rook-ceph-mon-endpoints` ConfigMap carry a
  `ceph.rook.io/disaster-protection` finalizer. With the operator stopped,
  nothing removes it, so a plain delete leaves them in place.
* lvm-localpv removes a logical volume without wiping it, so a new OSD volume
  carved from the same extents can still hold the previous cluster's
  BlueStore, and Rook refuses it as belonging to a different cluster.
* `dataDirHostPath` keeps the previous cluster's mon state.

With instance store the reset that clears all of it at once is replacing the
nodes, since AWS erases instance store on termination. Delete the OSD claims
first, while their nodes still exist, or the volume deletions hang.

A `handle_auth_bad_method ... [errno 13] RADOS permission denied` failure
with healthy quorum is not one of these. It is a Rook release too old for the
Ceph release's cephx key type, described in the module's
`operator_chart_version` variable.
