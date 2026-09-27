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

Two things bite when a cluster is torn down and rebuilt on nodes that outlive
it, both covered in the parent directory's notes:

* A `CephCluster` will not finish deleting while a `CephObjectStore` or
  `CephObjectStoreUser` still exists. Delete the dependents first; the
  operator log names them.
* Rook's `rook-ceph-mon`, `rook-ceph-mons-keyring` and
  `rook-ceph-admin-keyring` secrets are garbage-collected with the cluster,
  but not always before a new cluster starts bootstrapping. Confirm they are
  gone rather than assuming a delete took effect, or the mon may come up with
  an auth database the operator has no key for.
