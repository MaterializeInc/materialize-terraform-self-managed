# AWS, i8g.8xlarge storage pool

Ceph, rustfs and S3, measured from the same four nodes with the same matrix,
so the client hardware and the store hardware are both held constant.

## Setup

| | |
| --- | --- |
| Run | `t260928-ffeb2n`, 2026-09-28 |
| Cluster | EKS, us-east-1 |
| Storage pool | 4 x `i8g.8xlarge` (Graviton4, 32 vCPU, 2 x 3750 GB instance-store NVMe, guaranteed 25 Gbps), one Karpenter pool, all four in `us-east-1c` |
| Local volumes | `ephemeral-storage-setup lvm` into `instance-store-vg`, provisioned by openebs lvm-localpv |
| Client | `persistcli bench blob`, in-cluster on the pool's nodes, concurrency 32 |
| Matrix | 4 KiB, 1 MiB, 8 MiB; 4 GiB per cell, at most 32768 objects; 20 s of reads per cell |

`i8g.8xlarge` is the first size in the family with guaranteed bandwidth. The
smaller sizes are burstable, and a benchmark short enough to stay inside the
burst reports a rate the store cannot hold, which is what went wrong on
[`../aws-i8g-2xlarge`](../aws-i8g-2xlarge).

The stores:

| | |
| --- | --- |
| Ceph | Rook v1.20.7, Ceph v19.2.6. 3 mons, 4 OSDs one per host on 500 GiB volumes, 3x replication, `host` failure domain, 2 RGW gateways on the pool with `tcp_nodelay=1`, 16 MiB RGW chunks. As built by `object-store-rook-ceph` with nothing patched by hand. |
| rustfs | `rustfs/rustfs:1.0.0-rc.5`. 4 replicas, one 500 GiB drive each, erasure-coded across the four nodes. The portable module on the same nodes as Ceph, which sat idle while rustfs was measured. |
| S3 | The run's own bucket, same region, reached through IRSA as persist's `main` service account. |

## Results

Best in each row in bold. No store made a retry in any cell.

Writes, ops/s:

| | Ceph | rustfs | S3 |
| --- | --- | --- | --- |
| 4 KiB | **10,565** | 1,874 | 937 |
| 1 MiB | **2,108** | 1,268 | 484 |
| 8 MiB | 264 | **310** | 201 |

Writes, MiB/s:

| | Ceph | rustfs | S3 |
| --- | --- | --- | --- |
| 1 MiB | **2,108** | 1,268 | 484 |
| 8 MiB | 2,116 | **2,476** | 1,610 |

Reads, ops/s and MiB/s:

| | Ceph | rustfs | S3 |
| --- | --- | --- | --- |
| 4 KiB (ops/s) | **26,068** | 15,168 | 1,193 |
| 1 MiB (MiB/s) | **3,146** | 2,841 | 807 |
| 8 MiB (MiB/s) | **3,016** | 2,958 | 2,610 |

Read latency, ms:

| | Ceph p50 | rustfs p50 | S3 p50 | Ceph p99 | rustfs p99 | S3 p99 |
| --- | --- | --- | --- | --- | --- | --- |
| 4 KiB | **1.16** | 2.09 | 25.05 | **1.74** | 2.56 | 65.43 |
| 1 MiB | **7.11** | 9.67 | 31.59 | 38.68 | **21.78** | 180.91 |
| 8 MiB | **38.23** | 75.53 | 88.93 | 855.70 | 244.27 | **209.53** |

Deletes, ops/s:

| | Ceph | rustfs | S3 |
| --- | --- | --- | --- |
| 4 KiB | **8,317** | 1,696 | 909 |
| 1 MiB | **7,386** | 1,516 | 872 |
| 8 MiB | **7,137** | 1,362 | 928 |

## What the numbers say

**Small objects are where the stores differ, and Ceph leads all of it.** A
4 KiB operation is latency with almost no transfer, so these rows measure each
store's request path. Ceph reads 1.7x faster than rustfs and 22x faster than
S3, writes 5.6x and 11x faster, and deletes 4.9x to 5.2x and 7.7x to 9.1x
faster. S3 pays a round trip to a regional service on every operation, which
is why it trails both local stores by an order of magnitude.

**Large reads cannot be ranked from this run.** At 1 MiB and 8 MiB all three
stores sit at or past what one client can move. Ceph's 3,146 MiB/s is
26.4 Gbps, above the node's 25 Gbps, which is only possible because some of
its traffic never touched the network: the client shared a node with one of
Ceph's two gateways in every cell, and it always shares one with a rustfs
replica. S3 traffic always crosses the NIC. Ranking these needs clients on
several nodes, or a client on a node of the same type that hosts no store
daemons. The harness does neither yet.

**Large writes are closer, and inside the noise.** rustfs leads Ceph by 17% at
8 MiB and trails it by 40% at 1 MiB. Ceph writes three full replicas across the
network where rustfs writes erasure-coded shards, so the two do different
amounts of network work per byte. Both beat S3.

**Ceph has a long tail on large reads.** Its 8 MiB read p99 is 856 ms against
244 ms for rustfs and 210 ms for S3, although its median is the lowest of the
three. This was not investigated. A bimodal split between reads served by the
client's own node's gateway and reads served by the other would produce it.

## How much a cell can move between runs

S3 was measured twice on the same instance type, once before and once after
the pool's nodes were replaced ([`s3-first-run.csv`](s3-first-run.csv) and
[`s3.csv`](s3.csv)). Reads and large writes agreed within 4%. The 4 KiB write
cell moved 7% and the 1 MiB delete cell 15%. A difference between two stores
of less than about 15% in any single cell should not be read as a ranking.

## Materialize on Ceph

The run also served a Materialize instance with Ceph as its persist backend,
through the gateway as `s3://...@materialize/ceph`.

200,000 rows written and read back through `balancerd`, sum `20000100000`,
identical after `environmentd` was deleted and restarted, so that the second
read came from Ceph rather than from memory. No blob or parquet errors in any
`environmentd` or `clusterd` log.

Persist's own counters over the period after the restart:

| | |
| --- | --- |
| `blob_set` / `blob_get` / `blob_delete` | 2127 / 4052 / 1447 |
| `mz_persist_external_failed_count` | 0 |
| `mz_persist_blob_failures` | 0 |

## Ceph runs that are not results

Two other Ceph files are kept as evidence for fixes in the module, not as
measurements of Ceph:

- [`ceph-gateway-on-t4g-xlarge.csv`](ceph-gateway-on-t4g-xlarge.csv): both
  gateways had landed on burstable `t4g.xlarge` general-purpose nodes, one of
  them without a pod IP, because the gateway's placement was passed in the
  CephCluster's keyed form and Rook ignored it. Reads topped out near
  580 MiB/s.
- [`ceph-hand-patched.csv`](ceph-hand-patched.csv): gateways moved to the pool
  and Nagle disabled by hand, on Rook v1.16.7 with an emergency cipher override
  to get past the key-type incompatibility. Disabling Nagle alone took 4 KiB
  reads from 637 to 23,160 ops/s on that cluster. Writes were still flat at
  about 585 MiB/s at both 1 MiB and 8 MiB. That ceiling is gone in `ceph.csv`,
  but the Rook version, OSD spread, disks and zone all changed between the two,
  and which of them removed it was not isolated.
