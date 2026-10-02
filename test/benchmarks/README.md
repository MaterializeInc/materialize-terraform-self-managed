# Persist backend benchmarks

Results from `terraform-tests benchmark`, which drives a store through
persist's own S3 client (`persistcli bench blob`) from inside the cluster.

One directory per hardware profile. Each holds the raw CSV that the subcommand
writes, one file per run, plus a `combined.csv` merging the runs that make up a
comparison.

## Reading the CSVs

Columns are `persistcli bench blob`'s own, with `backend` and `volume` added by
the merge:

| column | meaning |
| --- | --- |
| `op` | `set`, `get`, `delete` or `list` |
| `size_bytes` | object size for the cell |
| `ops`, `bytes` | work completed in the cell |
| `ops_per_sec`, `mib_per_sec` | throughput |
| `p50_ms` … `max_ms` | per-operation latency |
| `retries` | retries persist's S3 client made |

`volume` names the byte budget per cell, which sets how many objects the cell
writes. It matters: see the sizing note below.

## Sizing a cell

`--bytes-per-cell` divided by the object size gives the object count, capped by
`--max-objects`. A cell needs enough objects to fill several waves at the
chosen concurrency, or the write rate measures start-up rather than the store.
The first AWS pass used the 128 MiB default, which at 8 MiB objects is 16
writes finishing in 0.27 s against a concurrency of 32, and it understated
every large-object figure:

| 8 MiB writes | ops/s | MiB/s |
| --- | --- | --- |
| 128 MiB per cell (16 objects) | 59.0 | 472 |
| 4 GiB per cell (512 objects) | 164.2 | 1314 |

Small objects are capped by `--max-objects` rather than by the byte budget, so
a 4 KiB cell is 4096 objects either way and needs no re-run.

## `list` is not comparable across stores

`--list-prefix=` lists the whole store, so the figure depends on what else the
store already holds rather than on the store's listing speed. A run against a
store holding earlier runs' objects lists more keys than it wrote. Compare
`list` only between cells known to have started from the same contents.
