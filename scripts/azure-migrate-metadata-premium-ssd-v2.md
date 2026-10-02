# Moving the Azure metadata database to Premium SSD v2

This runbook moves the Materialize metadata database of an existing Azure deployment from Premium SSD to Premium SSD v2. When it's done, your Terraform root tracks the new server and `terraform plan` shows no changes.

You can't do this by setting `storage_type = "PremiumV2_LRS"` on its own. Azure can't change a Flexible Server's storage type in place, so Terraform would delete the server and create an empty one, and Materialize would lose its metadata.

## How it works

[`azure-migrate-metadata-premium-ssd-v2.sh`](azure-migrate-metadata-premium-ssd-v2.sh) copies the server to a Premium SSD v2 read replica, then swaps the two with a planned switchover, so Materialize keeps its data:

1. Create the replica, named `<server>-v2`, and a virtual endpoint. The endpoint's writer hostname always points at the current primary.
2. Point Materialize at the writer hostname. This restarts environmentd.
3. Switch over. The replica becomes the primary, and the writer hostname follows it.
4. Point Materialize at the new server's own hostname, which restarts environmentd again. Then delete the endpoint and the old server.
5. Move Terraform state onto the new server, and apply.

The endpoint is only temporary. In Terraform, a virtual endpoint requires a replica to exist, so keeping one would mean paying for a second server for good. When the migration is done, the root declares one server, and nothing else is left behind.

**Downtime.** Materialize keeps running, apart from a few short interruptions. In two tests on the `enterprise` example, SQL was unavailable for about 2 minutes in total each time:

- 1 minute 35 seconds to 1 minute 50 seconds during the switchover. Azure quotes 1 to 3 minutes.
- About 20 seconds for one of the two environmentd restarts. The other caused no failed queries.

The whole migration took 26 to 30 minutes. Most of that was creating the replica, which doesn't affect Materialize. Run the migration in a maintenance window anyway.

## Before you start

You need:

- `az`, logged in to the subscription.
- `kubectl`, pointed at the cluster.
- `terraform` and `jq`.

The server must:

- be on a General Purpose or Memory Optimized SKU;
- have storage autogrow and high availability turned off;
- use private access (a delegated subnet);
- not be on PostgreSQL 13.

The script's `preflight` check verifies all of this, along with the defaults it assumes: a `database` module at `module.database`, and the instance in the `materialize-environment` namespace. Override those with the environment variables below.

**Don't run `terraform apply` on the root until the script has finished.** Partway through, the root and the state describe different servers, and an apply would point Materialize back at the old one.

## Edit the root

On your `database` module, point the root at the new server. In the examples, the three storage values live in `database_config`, which the module call passes through; add `server_name` to the module call itself:

```hcl
module "database" {
  # ...
  server_name        = "<server>-v2"
  storage_type       = "PremiumV2_LRS"
  storage_iops       = 3000 # the free baseline below 400 GiB
  storage_throughput = 125  # MB/s, the free baseline below 400 GiB
}
```

`<server>` is the current server's name, which defaults to `<prefix>-pg`. `preflight` prints the name it will use. Make the edit **before** `run`, or **after** `cleanup` if you run the phases one at a time. Either way, don't apply it yourself.

## Option A: all at once

```sh
./scripts/azure-migrate-metadata-premium-ssd-v2.sh <root> run
```

`run` starts with a plan-only check that your root edit is right. The only change it may plan in the database module is the server being replaced by `<server>-v2` on Premium SSD v2. If anything else shows up, it stops before touching anything.

It then runs every phase below in order. It asks you to confirm twice: before the switchover, and before deleting the old server. Set `YES=1` to skip both prompts.

## Option B: one phase at a time

Each phase is safe to re-run, and it refuses to run until the one before it has finished.

| Phase | What it does | Materialize |
|---|---|---|
| `preflight` | Checks the server can be migrated, and writes `.ssdv2-migration.env` in the root | up |
| `replica` | Creates the replica and the virtual endpoint (10 to 20 minutes) | up |
| `point-writer` | Points Materialize at the writer hostname | environmentd restarts |
| `switchover` | Runs the planned switchover | briefly unavailable |
| `point-direct` | Points Materialize at the new server's own hostname | environmentd restarts |
| `cleanup` | Deletes the virtual endpoint and the old server | up |
| *(edit the root)* | See [Edit the root](#edit-the-root) | up |
| `adopt` | Backs up the state, removes the old server from it, writes `import` blocks for the new one, and saves a plan. The plan must not create or replace anything in the database module | up |
| *(apply)* | `terraform -chdir=<root> apply .ssdv2-adopt.tfplan` | up |
| `finish` | Removes the generated files, and checks that the plan shows no changes to the database module or Materialize's backend secret. It lists any other changes in the root without failing | up |

```sh
./scripts/azure-migrate-metadata-premium-ssd-v2.sh <root> <phase>
```

## If something goes wrong

- **A phase failed:** fix the cause and run the same phase again. It picks up where it stopped.
- **Before the switchover:** `rollback` undoes everything. It points Materialize back at the old server, which restarts environmentd, deletes the replica and the endpoint, and removes the script's progress file. If you already edited the root, revert that edit too. Azure keeps a deleted server's name reserved for a while, so to try again soon after, set `NEW_SERVER` to another name, such as `<server>-v3`, and use it for `server_name` too. `preflight` checks the name is free.
- **Azure refused the switchover:** nothing has changed apart from where Materialize connects, so use `rollback`.
- **After the switchover:** the new server holds the data, so carry on with the remaining phases.
- **After `adopt`:** the state from before the move is saved as `terraform.tfstate.pre-ssdv2-<timestamp>` in the root.

## Environment variables

| Variable | Default | Meaning |
|---|---|---|
| `DATABASE_MODULE` | `module.database` | Address of the `database` module in your root |
| `INSTANCE_NAMESPACE` | `materialize-environment` | Namespace of the Materialize instance |
| `NEW_SERVER` | `<server>-v2` | Name of the new server, recorded by `preflight` |
| `ENDPOINT_NAME` | `<server>-ve` | Name of the temporary virtual endpoint |
| `YES` | unset | Set to `1` to skip the confirmation prompts |
