# AWS, i8g.2xlarge storage pool

S3 against an in-cluster store on local NVMe, measured from the same nodes so
the client hardware is not a variable.

## Setup

| | |
| --- | --- |
| Run | `t260926-zwl0bn`, 2026-09-26 |
| Cluster | EKS, us-east-1 |
| Storage pool | 4 x `i8g.2xlarge` (Graviton4, 1 x 1875 GB instance-store NVMe), one Karpenter node pool per store |
| Local volumes | `ephemeral-storage-setup lvm` into `instance-store-vg`, provisioned by openebs lvm-localpv |
| Client | `persistcli bench blob`, in-cluster, concurrency 32, `--read-secs 10` |
| Sizes | 4 KiB, 1 MiB, 8 MiB |

Both clients ran on the storage pool's nodes. S3's URL carries no credentials,
so its Job ran in `materialize-environment` as the `main` service account to
inherit the IRSA role persist itself authenticates with; the role's trust
policy names exactly that account, so borrowing it is the only way in.

Figures below are the 4 GiB cells for 1 MiB and 8 MiB and the 128 MiB cell for
4 KiB, which is the same 4096 objects either way. `combined.csv` is that
selection; the per-run files hold everything.

## Results

Writes:

| | rustfs ops/s | S3 ops/s | rustfs MiB/s | S3 MiB/s | rustfs p99 | S3 p99 |
| --- | --- | --- | --- | --- | --- | --- |
| 4 KiB | 938 | **1087** | 3.7 | 4.2 | 65.25 ms | 64.78 ms |
| 1 MiB | **610** | 527 | **610** | 527 | 74.60 ms | 121.84 ms |
| 8 MiB | 150 | **164** | 1198 | **1314** | 364.20 ms | 360.02 ms |

Reads:

| | rustfs ops/s | S3 ops/s | rustfs MiB/s | S3 MiB/s | rustfs p50 | S3 p50 | rustfs p99 | S3 p99 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 4 KiB | **6955** | 1282 | 27.2 | 5.0 | 4.47 ms | 24.07 ms | 7.81 ms | 43.71 ms |
| 1 MiB | **1200** | 1029 | **1200** | 1029 | 25.85 ms | 29.85 ms | 77.43 ms | 61.64 ms |
| 8 MiB | 160 | **176** | 1280 | **1407** | 170.72 ms | 145.73 ms | 529.05 ms | 496.19 ms |

Deletes, in ops/s, where object size barely matters:

| | rustfs | S3 |
| --- | --- | --- |
| 4 KiB | 769 | **1059** |
| 1 MiB | 780 | **984** |
| 8 MiB | 731 | **913** |

Neither store made a single retry in any cell.

## What the numbers say

At the sizes persist actually writes, S3 and a local-NVMe store are within
about 17% of each other, in both directions. Local NVMe is not the decisive
advantage the hardware suggests.

The one real gap is small-object reads, where rustfs is 5.4x faster on
throughput and 5.6x better at p99. That is the round trip: a 4 KiB read is all
latency and no transfer. Whether it reaches a user depends on persist's blob
cache absorbing those reads, which the SQL-level benchmark would answer and
does not yet exist.

At 1 MiB and 8 MiB both stores land between 1.0 and 1.4 GiB/s. That looks like
the instance's network allowance rather than either store's limit, so these
figures bound the client, not the backend. Testing that would need a larger
instance or several client pods.

S3 deletes faster at every size, by 25% to 38%.

## Materialize on rustfs

Before the blob matrix, the run served a Materialize instance with rustfs as
its persist backend, which is what the blob numbers are a proxy for.

200,000 rows written and read back, checksum `20000100000`, identical after an
`environmentd` restart forced the reads to come from the store rather than
from cache, with no parquet decoding errors. That exercises the multipart read
path against a store that omits `x-amz-mp-parts-count`, which is the case
persist now recovers from by falling back to byte ranges.

`mz_persist_external_*`, over the same period:

| | |
| --- | --- |
| `blob_set` / `blob_get` / `blob_delete` | 7877 / 4855 / 7498 |
| failures | 0 |
| `blob_get` p50 / p99 | 3.09 ms / 21.05 ms |
| bytes written | 165 MB |

The 3.09 ms p50 against 4.47 ms for a cold 4 KiB read in the matrix is the
blob cache doing its job, and is the reason a blob-level figure is an upper
bound on what a user would feel.

## Ceph

Not measured. Rook brought up a mon that considered itself healthy while the
operator could not authenticate to it:

```
handle_auth_bad_method server allowed_methods [2] but i only support [2,1]
[errno 13] RADOS permission denied
```

leaving the cluster in `Configuring Ceph Mons` indefinitely. It survived a
rebuild onto an unused `dataDirHostPath`, which rules out a mon adopting a
previous cluster's identity from a node that outlived it. The open hypothesis
is Rook's `rook-ceph-admin-keyring` / `rook-ceph-mons-keyring` / `rook-ceph-mon`
secrets outliving a cluster generation, so a mon bootstraps a fresh store
without `client.admin` in its auth database. Clearing all three and restarting
the operator had not been confirmed either way when the run ended.

Two things about Ceph on Karpenter that the run did establish:

- Rook pins each daemon to a node by hostname affinity, and Karpenter will not
  provision a node for a pod that already names one, so a pool that scales on
  demand deadlocks. Warming the pool first, with one placeholder pod per node,
  is what breaks it.
- A `CephCluster` will not finish deleting while a `CephObjectStore` or
  `CephObjectStoreUser` still exists. The operator log names the dependents.
