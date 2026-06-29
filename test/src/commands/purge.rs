//! Tag-scoped deletion of leaked AWS resources for a test run.
//!
//! When the AWS infrastructure test's `terraform destroy` fails, resources are
//! leaked, costing money and risking name/quota collisions on future runs. AWS
//! has no single-container delete (no resource-group/project equivalent), so
//! cleanup is tag-driven.
//!
//! Every taggable resource the tests create is stamped with a unique per-run
//! tag: the terraform provider sets `default_tags { tags = var.tags }` and the
//! harness populates `var.tags` with `TestRun=<test_run_id>` (see
//! [`crate::commands::init`]). The same `<test_run_id>` is the terraform
//! `name_prefix`, so the EKS cluster is named `<test_run_id>-eks`. This module
//! uses that id to find and delete everything belonging to a run, independent
//! of terraform state.
//!
//! ## Deletion order: a dependency DAG
//!
//! Resources are deleted respecting their teardown dependencies, running
//! independent subsystems concurrently and blocking only where a deletion must
//! finish before downstream cleanup can proceed:
//!
//! ```text
//!   node groups ──wait──▶ terminate instances ──┬─wait─▶ EKS cluster ─wait─▶ logs ┐
//!                                               ├──────▶ EBS volumes              │
//!                                               └──────▶ launch templates         │
//!   RDS instance ──wait──▶ RDS subnet group / parameter group ────────────────────┤
//!   NAT gateways ──wait──▶ release EIPs ──────────────────────────────────────────┤
//!   load balancers ───────────────────────────────────────────────────────────────┤
//!   VPC endpoints / S3 / SQS+EventBridge / KMS (fully independent) ───────────────┤
//!                                                                                 ▼
//!         ENIs ─▶ security groups ─▶ subnets ─▶ route tables ─▶ IGW ─▶ VPC   (+ IAM)
//! ```
//!
//! The cluster log group is deleted at the tail of the compute branch rather
//! than in a parallel branch: the EKS control plane recreates it while the
//! cluster drains, so it must be deleted only after the cluster-deletion wait.
//!
//! The blocking waits matter because each gates the network teardown: a managed
//! node group's ASG would relaunch terminated instances; the EKS cluster's
//! control-plane ENIs and the RDS instance both sit in the subnets; NAT gateways
//! hold the subnets and their EIPs. Built-in SDK deletion waiters are used for
//! these. The whole sweep is repeated a few times to mop up resources (e.g. ENIs
//! the load balancer controller releases lazily) that only become deletable once
//! their dependents are gone; once the big blockers are deleted, later passes
//! return from the waiters immediately.
//!
//! ## Error handling
//!
//! Each branch is best-effort and distinguishes two kinds of failure:
//!
//! * A **deletion** failure (one resource of many) must not stop the branch from
//!   deleting the rest, so [`handle`]/[`handle_wait`] record it in a per-branch
//!   error list and carry on. "Already gone" is treated as success.
//! * An **enumeration** failure (a `describe`/`list` that tells us what to
//!   delete) leaves the branch with nothing reliable to do, so it aborts the
//!   branch with `?`. [`Context`] attaches a human-readable label.
//!
//! A branch therefore returns `Result<Vec<String>>`: `Ok(errors)` carries the
//! soft per-resource failures, `Err(_)` is the hard enumeration failure. The
//! orchestration layer folds both into one list via [`collect`], so a single
//! branch blowing up never aborts the others.
//!
//! ## Resource types NOT covered by this sweep
//!
//! * Anything created outside terraform that carries neither `TestRun` nor a
//!   `*/<cluster>` cluster tag. In practice the in-cluster controllers do tag
//!   their resources with the cluster name (which embeds the run id), so they
//!   are covered: Karpenter EC2 instances (`TestRun`, via the EC2NodeClass),
//!   EBS CSI volumes (`kubernetes.io/cluster/<cluster>`), and AWS Load Balancer
//!   Controller load balancers / target groups (`elbv2.k8s.aws/cluster`). A
//!   future controller creating resources with neither tag would be missed.
//! * IAM resources are global and matched by `TestRun` tag (roles, customer-
//!   managed policies, OIDC providers) or run-id name prefix (instance profiles,
//!   policies); an IAM resource with neither would be missed.
//! * ACM certificates and Route53 zones: the example stack creates no per-run
//!   instances of these, so they are intentionally not swept. (The EKS cluster
//!   encryption KMS key *is* swept — see [`Ctx::kms_branch`].)
//!
//! This is destructive. It only ever deletes resources whose `TestRun` tag (or
//! a cluster tag embedding the run id) exactly matches a long, unique run id, so
//! an accidental match against an unrelated resource is effectively impossible.

use std::time::Duration;

use anyhow::{Context, Result, bail};
use aws_config::SdkConfig;
use aws_sdk_ec2::client::Waiters as _;
use aws_sdk_ec2::error::{ProvideErrorMetadata, SdkError};
use aws_sdk_ec2::types::Filter;
use aws_sdk_eks::client::Waiters as _;
use aws_sdk_elasticloadbalancingv2::client::Waiters as _;
use aws_sdk_rds::client::Waiters as _;

use crate::helpers::{aws_sdk_config, ci_log_group, read_tfvars, test_run_dir};
use crate::types::TfVars;

/// How many times to repeat the full ordered sweep. Each pass deletes resources
/// that became deletable when their dependents were removed in the prior pass.
const MAX_PASSES: u32 = 5;

/// Pause between passes, letting eventually-consistent deletes settle before the
/// next sweep re-enumerates (e.g. the ~60s SQS delete-propagation window, or
/// ENIs a controller releases lazily) so a still-draining resource isn't
/// re-reported as remaining.
const INTER_PASS_DELAY: Duration = Duration::from_secs(15);

/// Maximum time to wait for each blocking deletion to finish. Generous (at least
/// twice the typical observed duration) because these gate downstream cleanup
/// and an EKS cluster or RDS instance can take a long time to delete; the CI job
/// has a multi-hour budget.
const NODEGROUP_DELETE_WAIT: Duration = Duration::from_secs(30 * 60);
const CLUSTER_DELETE_WAIT: Duration = Duration::from_secs(30 * 60);
const INSTANCE_TERMINATE_WAIT: Duration = Duration::from_secs(10 * 60);
const NAT_GATEWAY_DELETE_WAIT: Duration = Duration::from_secs(30 * 60);
const RDS_DELETE_WAIT: Duration = Duration::from_secs(30 * 60);
const LB_DELETE_WAIT: Duration = Duration::from_secs(10 * 60);

/// Entry point for the `purge` subcommand. Reads the run's `terraform.tfvars`
/// to recover its region, profile, and `TestRun` tag, then sweeps.
pub async fn purge(test_run: &str) -> Result<()> {
    let dir = test_run_dir(test_run)?;
    let tfvars = read_tfvars(&dir)?;

    let (region, profile, run_id) = match tfvars {
        TfVars::Aws {
            aws_region,
            aws_profile,
            tags,
            ..
        } => {
            let run_id = tags
                .get("TestRun")
                .cloned()
                .unwrap_or_else(|| test_run.to_string());
            (aws_region, aws_profile, run_id)
        }
        _ => bail!("purge currently only supports AWS test runs"),
    };

    ci_log_group(&format!("Purge AWS resources for {run_id}"), || async {
        let config = aws_sdk_config(&region, Some(&profile)).await;
        let ctx = Ctx::new(&config, run_id, region);
        ctx.run().await
    })
    .await
}

/// Returns `true` if an AWS error code means the resource is already gone.
fn is_gone(code: &str) -> bool {
    code.ends_with("NotFound")
        || matches!(
            code,
            "NoSuchEntity"
                | "ResourceNotFoundException"
                | "DBInstanceNotFound"
                | "DBSubnetGroupNotFoundFault"
                | "LoadBalancerNotFound"
                | "NoSuchBucket"
                | "NoSuchTagSet"
                | "QueueDoesNotExist"
                | "AWS.SimpleQueueService.NonExistentQueue"
        )
}

/// Runs a single delete call, logging the outcome. Swallows "already gone"
/// errors; records the rest in `errors`. Returns `true` on success (including
/// already-gone).
fn handle<T, E, R>(errors: &mut Vec<String>, what: &str, res: Result<T, SdkError<E, R>>) -> bool
where
    E: ProvideErrorMetadata,
{
    match res {
        Ok(_) => {
            println!("  Deleted {what}");
            true
        }
        Err(e) => {
            let code = e.code().unwrap_or("Unknown").to_string();
            if is_gone(&code) {
                println!("  (already gone: {what})");
                true
            } else {
                let msg = e.message().unwrap_or("").to_string();
                println!("  ERROR deleting {what}: {code} {msg}");
                errors.push(format!("{what}: {code} {msg}"));
                false
            }
        }
    }
}

/// Records the outcome of a deletion waiter. A waiter for a "*Deleted" state
/// completes successfully when the resource is not found, so any error means it
/// did not finish draining in time (or a terminal failure occurred).
fn handle_wait<T, E: std::fmt::Debug>(errors: &mut Vec<String>, what: &str, res: Result<T, E>) {
    match res {
        Ok(_) => println!("  Confirmed deleted: {what}"),
        Err(e) => {
            let msg = format!("waiting for {what} to delete: {e:?}");
            println!("  {msg}");
            errors.push(msg);
        }
    }
}

/// Folds a branch's outcome into the running error list: the soft per-resource
/// failures it collected are appended as-is, while a hard enumeration failure
/// (propagated out of the branch with `?`) is recorded as a single entry. This
/// is what keeps the sweep best-effort — one branch aborting never stops the
/// others.
fn collect(errors: &mut Vec<String>, branch: Result<Vec<String>>) {
    match branch {
        Ok(soft) => errors.extend(soft),
        Err(e) => {
            println!("  ERROR: {e:#}");
            errors.push(format!("{e:#}"));
        }
    }
}

/// Clients and identifiers for sweeping one test run in one region. Cheap to
/// clone (the SDK clients are `Arc`-backed), so it is shared by `&` across the
/// concurrent branches of the sweep.
#[derive(Clone)]
struct Ctx {
    run_id: String,
    region: String,
    /// EKS cluster name (`<run_id>-eks`); also the value of the
    /// `kubernetes.io/cluster/<cluster>` and `elbv2.k8s.aws/cluster` tags that
    /// controller-created resources carry.
    cluster: String,
    ec2: aws_sdk_ec2::Client,
    eks: aws_sdk_eks::Client,
    rds: aws_sdk_rds::Client,
    elbv2: aws_sdk_elasticloadbalancingv2::Client,
    iam: aws_sdk_iam::Client,
    s3: aws_sdk_s3::Client,
    logs: aws_sdk_cloudwatchlogs::Client,
    sqs: aws_sdk_sqs::Client,
    events: aws_sdk_eventbridge::Client,
    kms: aws_sdk_kms::Client,
}

impl Ctx {
    fn new(config: &SdkConfig, run_id: String, region: String) -> Self {
        let cluster = format!("{run_id}-eks");
        Ctx {
            run_id,
            region,
            cluster,
            ec2: aws_sdk_ec2::Client::new(config),
            eks: aws_sdk_eks::Client::new(config),
            rds: aws_sdk_rds::Client::new(config),
            elbv2: aws_sdk_elasticloadbalancingv2::Client::new(config),
            iam: aws_sdk_iam::Client::new(config),
            s3: aws_sdk_s3::Client::new(config),
            logs: aws_sdk_cloudwatchlogs::Client::new(config),
            sqs: aws_sdk_sqs::Client::new(config),
            events: aws_sdk_eventbridge::Client::new(config),
            kms: aws_sdk_kms::Client::new(config),
        }
    }

    /// An EC2 `tag:TestRun=<run_id>` filter.
    fn tag_filter(&self) -> Filter {
        Filter::builder()
            .name("tag:TestRun")
            .values(&self.run_id)
            .build()
    }

    /// Instance ids tagged for the run that are not already terminating/gone,
    /// following the EC2 pagination token across pages.
    async fn live_instance_ids(&self) -> Result<Vec<String>> {
        let mut ids = Vec::new();
        let mut token: Option<String> = None;
        loop {
            let out = self
                .ec2
                .describe_instances()
                .filters(self.tag_filter())
                .filters(
                    Filter::builder()
                        .name("instance-state-name")
                        .values("pending")
                        .values("running")
                        .values("stopping")
                        .values("stopped")
                        .build(),
                )
                .set_next_token(token.clone())
                .send()
                .await
                .context("describe instances")?;
            for inst in out.reservations().iter().flat_map(|r| r.instances()) {
                if let Some(id) = inst.instance_id() {
                    ids.push(id.to_string());
                }
            }
            token = out.next_token().map(String::from);
            if token.is_none() {
                break;
            }
        }
        Ok(ids)
    }

    /// Returns the VPC id(s) tagged for this run.
    async fn vpc_ids(&self) -> Result<Vec<String>> {
        let out = self
            .ec2
            .describe_vpcs()
            .filters(self.tag_filter())
            .send()
            .await
            .context("describe vpcs")?;
        Ok(out
            .vpcs()
            .iter()
            .filter_map(|v| v.vpc_id().map(String::from))
            .collect())
    }

    // == compute branch ====================================================

    /// Deletes the run's EKS managed node groups and waits for them to finish.
    /// Must run *before* terminating instances: a managed node group's
    /// autoscaling group would otherwise relaunch the very instances we just
    /// terminated. Deleting the node group terminates its instances itself.
    async fn delete_node_groups(&self) -> Result<Vec<String>> {
        let mut errors = Vec::new();
        let nodegroups = match self
            .eks
            .list_nodegroups()
            .cluster_name(&self.cluster)
            .send()
            .await
        {
            Ok(out) => out.nodegroups().to_vec(),
            // No cluster means no node groups: nothing to do, not an error.
            Err(e) if is_gone(e.code().unwrap_or_default()) => return Ok(errors),
            Err(e) => return Err(e).context(format!("list node groups for {}", self.cluster)),
        };
        for ng in &nodegroups {
            handle(
                &mut errors,
                &format!("EKS node group {}/{ng}", self.cluster),
                self.eks
                    .delete_nodegroup()
                    .cluster_name(&self.cluster)
                    .nodegroup_name(ng)
                    .send()
                    .await,
            );
        }
        for ng in &nodegroups {
            handle_wait(
                &mut errors,
                &format!("EKS node group {}/{ng}", self.cluster),
                self.eks
                    .wait_until_nodegroup_deleted()
                    .cluster_name(&self.cluster)
                    .nodegroup_name(ng)
                    .wait(NODEGROUP_DELETE_WAIT)
                    .await,
            );
        }
        Ok(errors)
    }

    /// Terminates EC2 instances tagged for the run (chiefly the Karpenter-managed
    /// nodes; the managed base node group's instances are torn down by
    /// [`Self::delete_node_groups`], which must run first) and waits for them to
    /// terminate so dependent subnet/SG/ENI deletes can succeed.
    async fn terminate_instances(&self) -> Result<Vec<String>> {
        let mut errors = Vec::new();
        let ids = self.live_instance_ids().await?;
        if ids.is_empty() {
            return Ok(errors);
        }
        handle(
            &mut errors,
            &format!("{} EC2 instance(s)", ids.len()),
            self.ec2
                .terminate_instances()
                .set_instance_ids(Some(ids.clone()))
                .send()
                .await,
        );
        handle_wait(
            &mut errors,
            &format!("{} EC2 instance(s)", ids.len()),
            self.ec2
                .wait_until_instance_terminated()
                .set_instance_ids(Some(ids))
                .wait(INSTANCE_TERMINATE_WAIT)
                .await,
        );
        Ok(errors)
    }

    /// Deletes the EKS cluster and waits for it to finish (~10 min), which frees
    /// the control-plane ENIs that block subnet/VPC deletion. Run after node
    /// groups (a prerequisite) and instance termination.
    async fn delete_cluster(&self) -> Result<Vec<String>> {
        let mut errors = Vec::new();
        handle(
            &mut errors,
            &format!("EKS cluster {}", self.cluster),
            self.eks.delete_cluster().name(&self.cluster).send().await,
        );
        handle_wait(
            &mut errors,
            &format!("EKS cluster {}", self.cluster),
            self.eks
                .wait_until_cluster_deleted()
                .name(&self.cluster)
                .wait(CLUSTER_DELETE_WAIT)
                .await,
        );
        Ok(errors)
    }

    /// Deletes available EBS volumes: terraform-tagged (`TestRun`) and EBS CSI
    /// driver PVs (tagged `kubernetes.io/cluster/<cluster>=owned`). Depends on
    /// instances being terminated so the volumes have detached.
    async fn delete_volumes(&self) -> Result<Vec<String>> {
        let mut errors = Vec::new();
        let cluster_tag = format!("tag:kubernetes.io/cluster/{}", self.cluster);
        let filters = [
            self.tag_filter(),
            Filter::builder().name(&cluster_tag).values("owned").build(),
        ];
        let mut seen = std::collections::HashSet::new();
        for f in filters {
            let mut token: Option<String> = None;
            loop {
                let out = self
                    .ec2
                    .describe_volumes()
                    .filters(f.clone())
                    .set_next_token(token.clone())
                    .send()
                    .await
                    .context("describe volumes")?;
                for v in out.volumes() {
                    let vid = match v.volume_id() {
                        Some(id) => id.to_string(),
                        None => continue,
                    };
                    let available = v.state().map(|s| s.as_str()) == Some("available");
                    if !available || !seen.insert(vid.clone()) {
                        continue;
                    }
                    handle(
                        &mut errors,
                        &format!("EBS volume {vid}"),
                        self.ec2.delete_volume().volume_id(&vid).send().await,
                    );
                }
                token = out.next_token().map(String::from);
                if token.is_none() {
                    break;
                }
            }
        }
        Ok(errors)
    }

    /// Deletes launch templates tagged for the run (used by the node groups and
    /// Karpenter). Depends on instances/node groups being gone.
    async fn delete_launch_templates(&self) -> Result<Vec<String>> {
        let mut errors = Vec::new();
        let mut ids: Vec<String> = Vec::new();
        let mut token: Option<String> = None;
        loop {
            let out = self
                .ec2
                .describe_launch_templates()
                .filters(self.tag_filter())
                .set_next_token(token.clone())
                .send()
                .await
                .context("describe launch templates")?;
            ids.extend(
                out.launch_templates()
                    .iter()
                    .filter_map(|lt| lt.launch_template_id().map(String::from)),
            );
            token = out.next_token().map(String::from);
            if token.is_none() {
                break;
            }
        }
        for lid in ids {
            handle(
                &mut errors,
                &format!("launch template {lid}"),
                self.ec2
                    .delete_launch_template()
                    .launch_template_id(&lid)
                    .send()
                    .await,
            );
        }
        Ok(errors)
    }

    /// The full compute branch: node groups (wait) → instances (wait) → then the
    /// slow cluster delete overlapped with the now-unblocked volume and launch
    /// template deletes.
    async fn compute_branch(&self) -> Result<Vec<String>> {
        let mut errors = Vec::new();
        collect(&mut errors, self.delete_node_groups().await);
        collect(&mut errors, self.terminate_instances().await);
        let (cluster, volumes, templates) = tokio::join!(
            self.delete_cluster(),
            self.delete_volumes(),
            self.delete_launch_templates(),
        );
        collect(&mut errors, cluster);
        collect(&mut errors, volumes);
        collect(&mut errors, templates);
        // The EKS control plane recreates its cluster log group while draining,
        // so delete it only now that delete_cluster has waited for the cluster to
        // be fully gone — otherwise the deleted group reappears behind us.
        collect(&mut errors, self.delete_log_groups().await);
        Ok(errors)
    }

    // == RDS branch ========================================================

    /// Requests deletion of RDS instances tagged for the run and waits for them
    /// to finish (~5 min), then deletes the now-orphaned DB subnet group. The
    /// instance sits in the run's subnets, so this gates subnet/VPC teardown.
    async fn rds_branch(&self) -> Result<Vec<String>> {
        let mut errors = Vec::new();

        let mut identifiers = Vec::new();
        let mut marker: Option<String> = None;
        loop {
            let out = self
                .rds
                .describe_db_instances()
                .set_marker(marker.clone())
                .send()
                .await
                .context("describe db instances")?;
            for db in out.db_instances() {
                let is_match = db
                    .tag_list()
                    .iter()
                    .any(|t| t.key() == Some("TestRun") && t.value() == Some(&self.run_id));
                if let (true, Some(ident)) = (is_match, db.db_instance_identifier()) {
                    identifiers.push(ident.to_string());
                }
            }
            marker = out.marker().map(String::from);
            if marker.is_none() {
                break;
            }
        }
        for ident in &identifiers {
            handle(
                &mut errors,
                &format!("RDS instance {ident}"),
                self.rds
                    .delete_db_instance()
                    .db_instance_identifier(ident)
                    .skip_final_snapshot(true)
                    .delete_automated_backups(true)
                    .send()
                    .await,
            );
        }
        for ident in &identifiers {
            handle_wait(
                &mut errors,
                &format!("RDS instance {ident}"),
                self.rds
                    .wait_until_db_instance_deleted()
                    .db_instance_identifier(ident)
                    .wait(RDS_DELETE_WAIT)
                    .await,
            );
        }

        // DB subnet groups can only be deleted once their instance is gone.
        let mut marker: Option<String> = None;
        loop {
            let out = self
                .rds
                .describe_db_subnet_groups()
                .set_marker(marker.clone())
                .send()
                .await
                .context("describe db subnet groups")?;
            for sg in out.db_subnet_groups() {
                let arn = match sg.db_subnet_group_arn() {
                    Some(a) => a,
                    None => continue,
                };
                // Per-group tag read: on failure, skip this group rather than
                // abort the whole branch.
                let tags = match self
                    .rds
                    .list_tags_for_resource()
                    .resource_name(arn)
                    .send()
                    .await
                {
                    Ok(t) => t,
                    Err(e) => {
                        errors.push(format!("list tags for {arn}: {e}"));
                        continue;
                    }
                };
                let is_match = tags
                    .tag_list()
                    .iter()
                    .any(|t| t.key() == Some("TestRun") && t.value() == Some(&self.run_id));
                if let (true, Some(name)) = (is_match, sg.db_subnet_group_name()) {
                    handle(
                        &mut errors,
                        &format!("RDS subnet group {name}"),
                        self.rds
                            .delete_db_subnet_group()
                            .db_subnet_group_name(name)
                            .send()
                            .await,
                    );
                }
            }
            marker = out.marker().map(String::from);
            if marker.is_none() {
                break;
            }
        }

        // DB parameter groups, like subnet groups, can only be deleted once the
        // instance referencing them is gone.
        for name in self.tagged_db_parameter_group_names().await? {
            handle(
                &mut errors,
                &format!("RDS parameter group {name}"),
                self.rds
                    .delete_db_parameter_group()
                    .db_parameter_group_name(&name)
                    .send()
                    .await,
            );
        }
        Ok(errors)
    }

    /// Names of DB parameter groups tagged for this run. RDS exposes no
    /// server-side tag filter, so this lists every group and reads each one's
    /// tags. Shared by the delete in [`Self::rds_branch`] and the completion
    /// check in [`Self::remaining`].
    async fn tagged_db_parameter_group_names(&self) -> Result<Vec<String>> {
        let mut names = Vec::new();
        let mut marker: Option<String> = None;
        loop {
            let out = self
                .rds
                .describe_db_parameter_groups()
                .set_marker(marker.clone())
                .send()
                .await
                .context("describe db parameter groups")?;
            for pg in out.db_parameter_groups() {
                let arn = match pg.db_parameter_group_arn() {
                    Some(a) => a,
                    None => continue,
                };
                // Per-group tag read: on failure, skip rather than abort.
                let tags = match self
                    .rds
                    .list_tags_for_resource()
                    .resource_name(arn)
                    .send()
                    .await
                {
                    Ok(t) => t,
                    Err(_) => continue,
                };
                let is_match = tags
                    .tag_list()
                    .iter()
                    .any(|t| t.key() == Some("TestRun") && t.value() == Some(&self.run_id));
                if let (true, Some(name)) = (is_match, pg.db_parameter_group_name()) {
                    names.push(name.to_string());
                }
            }
            marker = out.marker().map(String::from);
            if marker.is_none() {
                break;
            }
        }
        Ok(names)
    }

    // == Karpenter interruption (SQS + EventBridge; independent) ============

    /// Deletes the Karpenter spot-interruption plumbing: the SQS queue
    /// (`<run>-interruption`) and the EventBridge rules (`<run>-*-interruption`)
    /// that feed it. Both are created by the Karpenter terraform module and
    /// carry the run id as a name prefix, so they are matched by name — the same
    /// convention used for instance profiles. Fully independent of the network
    /// spine, so it runs in the first concurrent stage.
    async fn karpenter_branch(&self) -> Result<Vec<String>> {
        let mut errors = Vec::new();
        collect(&mut errors, self.delete_interruption_queues().await);
        collect(&mut errors, self.delete_interruption_rules().await);
        Ok(errors)
    }

    /// Queue URLs whose name begins with the run id. `list_queues` matches on a
    /// literal name prefix, so this is a single (paginated) call.
    async fn interruption_queue_urls(&self) -> Result<Vec<String>> {
        let mut urls = Vec::new();
        let mut token: Option<String> = None;
        loop {
            let out = self
                .sqs
                .list_queues()
                .queue_name_prefix(&self.run_id)
                .set_next_token(token.clone())
                .send()
                .await
                .context("list sqs queues")?;
            urls.extend(out.queue_urls().iter().cloned());
            token = out.next_token().map(String::from);
            if token.is_none() {
                break;
            }
        }
        Ok(urls)
    }

    async fn delete_interruption_queues(&self) -> Result<Vec<String>> {
        let mut errors = Vec::new();
        for url in self.interruption_queue_urls().await? {
            handle(
                &mut errors,
                &format!("SQS queue {url}"),
                self.sqs.delete_queue().queue_url(&url).send().await,
            );
        }
        Ok(errors)
    }

    /// EventBridge rule names whose name begins with the run id. `list_rules`
    /// matches on a literal name prefix.
    async fn interruption_rule_names(&self) -> Result<Vec<String>> {
        let mut names = Vec::new();
        let mut token: Option<String> = None;
        loop {
            let out = self
                .events
                .list_rules()
                .name_prefix(&self.run_id)
                .set_next_token(token.clone())
                .send()
                .await
                .context("list eventbridge rules")?;
            names.extend(
                out.rules()
                    .iter()
                    .filter_map(|r| r.name().map(String::from)),
            );
            token = out.next_token().map(String::from);
            if token.is_none() {
                break;
            }
        }
        Ok(names)
    }

    async fn delete_interruption_rules(&self) -> Result<Vec<String>> {
        let mut errors = Vec::new();
        for name in self.interruption_rule_names().await? {
            // A rule cannot be deleted while it still has targets, so drain them
            // first.
            match self.events.list_targets_by_rule().rule(&name).send().await {
                Ok(out) => {
                    let ids: Vec<String> =
                        out.targets().iter().map(|t| t.id().to_string()).collect();
                    if !ids.is_empty() {
                        handle(
                            &mut errors,
                            &format!("targets of rule {name}"),
                            self.events
                                .remove_targets()
                                .rule(&name)
                                .set_ids(Some(ids))
                                .send()
                                .await,
                        );
                    }
                }
                Err(e) if !is_gone(e.code().unwrap_or_default()) => {
                    errors.push(format!("list targets of rule {name}: {e}"));
                }
                Err(_) => {}
            }
            handle(
                &mut errors,
                &format!("EventBridge rule {name}"),
                self.events.delete_rule().name(&name).send().await,
            );
        }
        Ok(errors)
    }

    // == KMS (independent) =================================================

    /// Schedules deletion of the run's customer-managed KMS keys (the EKS
    /// cluster encryption key) and removes their aliases. KMS has no immediate
    /// delete: [`schedule_key_deletion`] sets a pending window (we request the
    /// 7-day minimum), after which AWS deletes the key. A key already pending
    /// deletion is treated as done. Matched by `TestRun` tag, like the IAM
    /// resources.
    async fn kms_branch(&self) -> Result<Vec<String>> {
        let mut errors = Vec::new();
        for key_id in self.tagged_kms_key_ids().await? {
            // Delete the key's aliases first — they are released immediately and
            // would otherwise linger (and collide on a future run) for the whole
            // pending-deletion window.
            match self.kms.list_aliases().key_id(&key_id).send().await {
                Ok(out) => {
                    for a in out.aliases() {
                        if let Some(name) = a.alias_name() {
                            handle(
                                &mut errors,
                                &format!("KMS alias {name}"),
                                self.kms.delete_alias().alias_name(name).send().await,
                            );
                        }
                    }
                }
                Err(e) if !is_gone(e.code().unwrap_or_default()) => {
                    errors.push(format!("list aliases of key {key_id}: {e}"));
                }
                Err(_) => {}
            }
            handle(
                &mut errors,
                &format!("KMS key {key_id} (scheduled for deletion)"),
                self.kms
                    .schedule_key_deletion()
                    .key_id(&key_id)
                    .pending_window_in_days(7)
                    .send()
                    .await,
            );
        }
        Ok(errors)
    }

    /// Ids of enabled, customer-managed KMS keys tagged for this run. Keys
    /// already pending deletion are excluded — they are effectively gone, so
    /// neither the delete nor the [`Self::remaining`] check should act on them.
    /// AWS-managed keys (which we cannot schedule for deletion) are skipped.
    async fn tagged_kms_key_ids(&self) -> Result<Vec<String>> {
        let mut ids = Vec::new();
        let mut marker: Option<String> = None;
        loop {
            let out = self
                .kms
                .list_keys()
                .set_marker(marker.clone())
                .send()
                .await
                .context("list kms keys")?;
            for k in out.keys() {
                let key_id = match k.key_id() {
                    Some(id) => id,
                    None => continue,
                };
                // describe_key tells us manager + state; list_resource_tags can
                // fail on keys we do not control. On any error, skip the key
                // rather than abort the whole listing.
                let Ok(desc) = self.kms.describe_key().key_id(key_id).send().await else {
                    continue;
                };
                let meta = match desc.key_metadata() {
                    Some(m) => m,
                    None => continue,
                };
                let customer_managed =
                    meta.key_manager() == Some(&aws_sdk_kms::types::KeyManagerType::Customer);
                let pending = matches!(
                    meta.key_state(),
                    Some(aws_sdk_kms::types::KeyState::PendingDeletion)
                );
                if !customer_managed || pending {
                    continue;
                }
                let Ok(tags) = self.kms.list_resource_tags().key_id(key_id).send().await else {
                    continue;
                };
                if tags
                    .tags()
                    .iter()
                    .any(|t| t.tag_key() == "TestRun" && t.tag_value() == self.run_id)
                {
                    ids.push(key_id.to_string());
                }
            }
            marker = out.next_marker().map(String::from);
            if marker.is_none() {
                break;
            }
        }
        Ok(ids)
    }

    // == NAT branch ========================================================

    /// Deletes NAT gateways tagged for the run, waits for them to reach
    /// `deleted`, then releases their now-detached EIPs. Gates subnet teardown.
    async fn nat_branch(&self) -> Result<Vec<String>> {
        let mut errors = Vec::new();
        let mut ids: Vec<String> = Vec::new();
        let mut token: Option<String> = None;
        loop {
            let out = self
                .ec2
                .describe_nat_gateways()
                .filter(self.tag_filter())
                .filter(
                    Filter::builder()
                        .name("state")
                        .values("pending")
                        .values("available")
                        .values("failed")
                        .build(),
                )
                .set_next_token(token.clone())
                .send()
                .await
                .context("describe nat gateways")?;
            ids.extend(
                out.nat_gateways()
                    .iter()
                    .filter_map(|g| g.nat_gateway_id().map(String::from)),
            );
            token = out.next_token().map(String::from);
            if token.is_none() {
                break;
            }
        }
        for gid in &ids {
            handle(
                &mut errors,
                &format!("NAT gateway {gid}"),
                self.ec2
                    .delete_nat_gateway()
                    .nat_gateway_id(gid)
                    .send()
                    .await,
            );
        }
        if !ids.is_empty() {
            handle_wait(
                &mut errors,
                &format!("{} NAT gateway(s)", ids.len()),
                self.ec2
                    .wait_until_nat_gateway_deleted()
                    .set_nat_gateway_ids(Some(ids))
                    .wait(NAT_GATEWAY_DELETE_WAIT)
                    .await,
            );
        }
        collect(&mut errors, self.release_eips().await);
        Ok(errors)
    }

    /// Releases Elastic IPs tagged for the run. `describe_addresses` is not a
    /// paginated API (it returns every matching address in one response), so no
    /// continuation loop is needed here.
    async fn release_eips(&self) -> Result<Vec<String>> {
        let mut errors = Vec::new();
        let out = self
            .ec2
            .describe_addresses()
            .filters(self.tag_filter())
            .send()
            .await
            .context("describe addresses")?;
        for a in out.addresses() {
            if let Some(alloc) = a.allocation_id() {
                handle(
                    &mut errors,
                    &format!("Elastic IP {alloc}"),
                    self.ec2.release_address().allocation_id(alloc).send().await,
                );
            }
        }
        Ok(errors)
    }

    // == load balancers (independent) ======================================

    /// Deletes load balancers and target groups tagged either `TestRun` (the
    /// terraform NLB module) or `elbv2.k8s.aws/cluster=<cluster>` (created by
    /// the AWS Load Balancer Controller for in-cluster Services).
    async fn delete_load_balancers(&self) -> Result<Vec<String>> {
        let mut errors = Vec::new();

        let mut lb_arns = Vec::new();
        let mut marker: Option<String> = None;
        loop {
            let out = self
                .elbv2
                .describe_load_balancers()
                .set_marker(marker.clone())
                .send()
                .await
                .context("describe load balancers")?;
            lb_arns.extend(
                out.load_balancers()
                    .iter()
                    .filter_map(|lb| lb.load_balancer_arn().map(String::from)),
            );
            marker = out.next_marker().map(String::from);
            if marker.is_none() {
                break;
            }
        }
        let matched_lbs = self.filter_by_lb_tags(&lb_arns, &mut errors).await;
        for arn in &matched_lbs {
            handle(
                &mut errors,
                &format!("load balancer {arn}"),
                self.elbv2
                    .delete_load_balancer()
                    .load_balancer_arn(arn)
                    .send()
                    .await,
            );
        }
        // Wait for the LBs to actually go away: their ENIs sit in the run's
        // subnets and block the network spine, and their target groups cannot
        // be deleted while the LB still references them.
        if !matched_lbs.is_empty() {
            handle_wait(
                &mut errors,
                &format!("{} load balancer(s)", matched_lbs.len()),
                self.elbv2
                    .wait_until_load_balancers_deleted()
                    .set_load_balancer_arns(Some(matched_lbs))
                    .wait(LB_DELETE_WAIT)
                    .await,
            );
        }

        let mut tg_arns = Vec::new();
        let mut marker: Option<String> = None;
        loop {
            let out = self
                .elbv2
                .describe_target_groups()
                .set_marker(marker.clone())
                .send()
                .await
                .context("describe target groups")?;
            tg_arns.extend(
                out.target_groups()
                    .iter()
                    .filter_map(|tg| tg.target_group_arn().map(String::from)),
            );
            marker = out.next_marker().map(String::from);
            if marker.is_none() {
                break;
            }
        }
        for arn in self.filter_by_lb_tags(&tg_arns, &mut errors).await {
            handle(
                &mut errors,
                &format!("target group {arn}"),
                self.elbv2
                    .delete_target_group()
                    .target_group_arn(&arn)
                    .send()
                    .await,
            );
        }
        Ok(errors)
    }

    /// Of the given ELBv2 ARNs, returns those whose tags match this run. A
    /// failure to read one chunk's tags is recorded and the chunk skipped, so
    /// partial progress is preserved.
    async fn filter_by_lb_tags(&self, arns: &[String], errors: &mut Vec<String>) -> Vec<String> {
        let mut matched = Vec::new();
        for chunk in arns.chunks(20) {
            let out = match self
                .elbv2
                .describe_tags()
                .set_resource_arns(Some(chunk.to_vec()))
                .send()
                .await
            {
                Ok(o) => o,
                Err(e) => {
                    errors.push(format!("describe elbv2 tags: {e}"));
                    continue;
                }
            };
            for d in out.tag_descriptions() {
                let is_match = d.tags().iter().any(|t| {
                    (t.key() == Some("TestRun") && t.value() == Some(self.run_id.as_str()))
                        || (t.key() == Some("elbv2.k8s.aws/cluster")
                            && t.value() == Some(self.cluster.as_str()))
                });
                if is_match && let Some(arn) = d.resource_arn() {
                    matched.push(arn.to_string());
                }
            }
        }
        matched
    }

    // == VPC endpoints / S3 / logs (independent) ===========================

    /// Deletes VPC endpoints tagged for the run.
    async fn delete_vpc_endpoints(&self) -> Result<Vec<String>> {
        let mut errors = Vec::new();
        let mut ids: Vec<String> = Vec::new();
        let mut token: Option<String> = None;
        loop {
            let out = self
                .ec2
                .describe_vpc_endpoints()
                .filters(self.tag_filter())
                .set_next_token(token.clone())
                .send()
                .await
                .context("describe vpc endpoints")?;
            ids.extend(
                out.vpc_endpoints()
                    .iter()
                    .filter_map(|e| e.vpc_endpoint_id().map(String::from)),
            );
            token = out.next_token().map(String::from);
            if token.is_none() {
                break;
            }
        }
        if !ids.is_empty() {
            handle(
                &mut errors,
                &format!("{} VPC endpoint(s)", ids.len()),
                self.ec2
                    .delete_vpc_endpoints()
                    .set_vpc_endpoint_ids(Some(ids))
                    .send()
                    .await,
            );
        }
        Ok(errors)
    }

    /// Lists every S3 bucket, following the continuation token across pages.
    async fn list_all_buckets(&self) -> Result<Vec<String>> {
        let mut names = Vec::new();
        let mut token: Option<String> = None;
        loop {
            let out = self
                .s3
                .list_buckets()
                .set_continuation_token(token.clone())
                .send()
                .await
                .context("list buckets")?;
            names.extend(
                out.buckets()
                    .iter()
                    .filter_map(|b| b.name().map(String::from)),
            );
            token = out.continuation_token().map(String::from);
            if token.is_none() {
                break;
            }
        }
        Ok(names)
    }

    /// Empties and deletes S3 buckets tagged for the run.
    async fn delete_buckets(&self) -> Result<Vec<String>> {
        let mut errors = Vec::new();
        for name in self.list_all_buckets().await? {
            let tagging = match self.s3.get_bucket_tagging().bucket(&name).send().await {
                Ok(t) => t,
                Err(e) => {
                    // No tag set, gone, or in another region: not ours, skip
                    // quietly. Anything else is an unexpected failure to read a
                    // bucket we might own, so record it.
                    let code = e.code().unwrap_or_default();
                    if !is_gone(code)
                        && code != "PermanentRedirect"
                        && code != "AuthorizationHeaderMalformed"
                    {
                        errors.push(format!("get bucket tagging for {name}: {code}"));
                    }
                    continue;
                }
            };
            let is_match = tagging
                .tag_set()
                .iter()
                .any(|t| t.key() == "TestRun" && t.value() == self.run_id);
            if !is_match {
                continue;
            }
            self.empty_and_delete_bucket(&name, &mut errors).await;
        }
        Ok(errors)
    }

    async fn empty_and_delete_bucket(&self, name: &str, errors: &mut Vec<String>) {
        println!("  Emptying and deleting S3 bucket {name}");
        let mut key_marker: Option<String> = None;
        let mut version_marker: Option<String> = None;
        loop {
            let out = match self
                .s3
                .list_object_versions()
                .bucket(name)
                .set_key_marker(key_marker.clone())
                .set_version_id_marker(version_marker.clone())
                .send()
                .await
            {
                Ok(o) => o,
                Err(e) => {
                    if !is_gone(e.code().unwrap_or_default()) {
                        errors.push(format!("list objects in {name}: {e}"));
                    }
                    return;
                }
            };

            let mut objects = Vec::new();
            for v in out.versions() {
                if let Some(key) = v.key() {
                    let mut id = aws_sdk_s3::types::ObjectIdentifier::builder().key(key);
                    if let Some(vid) = v.version_id() {
                        id = id.version_id(vid);
                    }
                    if let Ok(obj) = id.build() {
                        objects.push(obj);
                    }
                }
            }
            for m in out.delete_markers() {
                if let Some(key) = m.key() {
                    let mut id = aws_sdk_s3::types::ObjectIdentifier::builder().key(key);
                    if let Some(vid) = m.version_id() {
                        id = id.version_id(vid);
                    }
                    if let Ok(obj) = id.build() {
                        objects.push(obj);
                    }
                }
            }

            for chunk in objects.chunks(1000) {
                if let Ok(del) = aws_sdk_s3::types::Delete::builder()
                    .set_objects(Some(chunk.to_vec()))
                    .quiet(true)
                    .build()
                    && let Err(e) = self
                        .s3
                        .delete_objects()
                        .bucket(name)
                        .delete(del)
                        .send()
                        .await
                {
                    errors.push(format!("delete objects in {name}: {e}"));
                }
            }

            if out.is_truncated() == Some(true) {
                key_marker = out.next_key_marker().map(String::from);
                version_marker = out.next_version_id_marker().map(String::from);
            } else {
                break;
            }
        }
        handle(
            errors,
            &format!("S3 bucket {name}"),
            self.s3.delete_bucket().bucket(name).send().await,
        );
    }

    /// Deletes the EKS cluster log group (`/aws/eks/<cluster>/...`). Called from
    /// the compute branch *after* the cluster-deletion wait: the control plane
    /// recreates the group while it drains, so deleting it earlier (or in a
    /// parallel branch) would leave a recreated group behind.
    async fn delete_log_groups(&self) -> Result<Vec<String>> {
        let mut errors = Vec::new();
        let prefix = format!("/aws/eks/{}/", self.cluster);
        let mut token: Option<String> = None;
        loop {
            let out = self
                .logs
                .describe_log_groups()
                .log_group_name_prefix(&prefix)
                .set_next_token(token.clone())
                .send()
                .await
                .context("describe log groups")?;
            for lg in out.log_groups() {
                if let Some(lname) = lg.log_group_name() {
                    handle(
                        &mut errors,
                        &format!("log group {lname}"),
                        self.logs
                            .delete_log_group()
                            .log_group_name(lname)
                            .send()
                            .await,
                    );
                }
            }
            token = out.next_token().map(String::from);
            if token.is_none() {
                break;
            }
        }
        Ok(errors)
    }

    // == network spine (serial; runs after the barrier) ====================

    /// Deletes leftover available ENIs in the run's VPC (left by the VPC CNI or
    /// load balancer controller after their owners are gone).
    async fn delete_network_interfaces(&self) -> Result<Vec<String>> {
        let mut errors = Vec::new();
        for vpc_id in self.vpc_ids().await? {
            let mut ids: Vec<String> = Vec::new();
            let mut token: Option<String> = None;
            loop {
                let out = self
                    .ec2
                    .describe_network_interfaces()
                    .filters(Filter::builder().name("vpc-id").values(&vpc_id).build())
                    .filters(Filter::builder().name("status").values("available").build())
                    .set_next_token(token.clone())
                    .send()
                    .await
                    .context(format!("describe network interfaces in {vpc_id}"))?;
                ids.extend(
                    out.network_interfaces()
                        .iter()
                        .filter_map(|eni| eni.network_interface_id().map(String::from)),
                );
                token = out.next_token().map(String::from);
                if token.is_none() {
                    break;
                }
            }
            for nid in ids {
                handle(
                    &mut errors,
                    &format!("network interface {nid}"),
                    self.ec2
                        .delete_network_interface()
                        .network_interface_id(&nid)
                        .send()
                        .await,
                );
            }
        }
        Ok(errors)
    }

    /// Deletes the non-default security groups in the run's VPC. Revokes all
    /// rules first so cross-references between groups do not block deletion,
    /// then loops because deletion order still matters.
    async fn delete_security_groups(&self) -> Result<Vec<String>> {
        let mut errors = Vec::new();
        for vpc_id in self.vpc_ids().await? {
            let mut groups: Vec<aws_sdk_ec2::types::SecurityGroup> = Vec::new();
            let mut token: Option<String> = None;
            loop {
                let out = self
                    .ec2
                    .describe_security_groups()
                    .filters(Filter::builder().name("vpc-id").values(&vpc_id).build())
                    .set_next_token(token.clone())
                    .send()
                    .await
                    .context(format!("describe security groups in {vpc_id}"))?;
                groups.extend(
                    out.security_groups()
                        .iter()
                        .filter(|sg| sg.group_name() != Some("default"))
                        .cloned(),
                );
                token = out.next_token().map(String::from);
                if token.is_none() {
                    break;
                }
            }

            for sg in &groups {
                let gid = match sg.group_id() {
                    Some(id) => id,
                    None => continue,
                };
                if !sg.ip_permissions().is_empty() {
                    handle(
                        &mut errors,
                        &format!("ingress rules of {gid}"),
                        self.ec2
                            .revoke_security_group_ingress()
                            .group_id(gid)
                            .set_ip_permissions(Some(sg.ip_permissions().to_vec()))
                            .send()
                            .await,
                    );
                }
                if !sg.ip_permissions_egress().is_empty() {
                    handle(
                        &mut errors,
                        &format!("egress rules of {gid}"),
                        self.ec2
                            .revoke_security_group_egress()
                            .group_id(gid)
                            .set_ip_permissions(Some(sg.ip_permissions_egress().to_vec()))
                            .send()
                            .await,
                    );
                }
            }

            let mut remaining: Vec<String> = groups
                .iter()
                .filter_map(|sg| sg.group_id().map(String::from))
                .collect();
            while !remaining.is_empty() {
                let mut still = Vec::new();
                for gid in &remaining {
                    let ok = handle(
                        &mut errors,
                        &format!("security group {gid}"),
                        self.ec2.delete_security_group().group_id(gid).send().await,
                    );
                    if !ok {
                        still.push(gid.clone());
                    }
                }
                if still.len() == remaining.len() {
                    break; // no progress; report leftovers
                }
                remaining = still;
            }
        }
        Ok(errors)
    }

    /// Deletes subnets tagged for the run.
    async fn delete_subnets(&self) -> Result<Vec<String>> {
        let mut errors = Vec::new();
        let mut ids: Vec<String> = Vec::new();
        let mut token: Option<String> = None;
        loop {
            let out = self
                .ec2
                .describe_subnets()
                .filters(self.tag_filter())
                .set_next_token(token.clone())
                .send()
                .await
                .context("describe subnets")?;
            ids.extend(
                out.subnets()
                    .iter()
                    .filter_map(|s| s.subnet_id().map(String::from)),
            );
            token = out.next_token().map(String::from);
            if token.is_none() {
                break;
            }
        }
        for sid in ids {
            handle(
                &mut errors,
                &format!("subnet {sid}"),
                self.ec2.delete_subnet().subnet_id(&sid).send().await,
            );
        }
        Ok(errors)
    }

    /// Deletes non-main route tables tagged for the run, disassociating them
    /// first. The main route table is deleted with the VPC.
    async fn delete_route_tables(&self) -> Result<Vec<String>> {
        let mut errors = Vec::new();
        let mut route_tables: Vec<aws_sdk_ec2::types::RouteTable> = Vec::new();
        let mut token: Option<String> = None;
        loop {
            let out = self
                .ec2
                .describe_route_tables()
                .filters(self.tag_filter())
                .set_next_token(token.clone())
                .send()
                .await
                .context("describe route tables")?;
            route_tables.extend(out.route_tables().iter().cloned());
            token = out.next_token().map(String::from);
            if token.is_none() {
                break;
            }
        }
        for rt in route_tables {
            for assoc in rt.associations() {
                if assoc.main() == Some(true) {
                    continue;
                }
                if let Some(aid) = assoc.route_table_association_id() {
                    handle(
                        &mut errors,
                        &format!("route table association {aid}"),
                        self.ec2
                            .disassociate_route_table()
                            .association_id(aid)
                            .send()
                            .await,
                    );
                }
            }
            if rt.associations().iter().any(|a| a.main() == Some(true)) {
                continue;
            }
            if let Some(rid) = rt.route_table_id() {
                handle(
                    &mut errors,
                    &format!("route table {rid}"),
                    self.ec2
                        .delete_route_table()
                        .route_table_id(rid)
                        .send()
                        .await,
                );
            }
        }
        Ok(errors)
    }

    /// Detaches and deletes internet gateways tagged for the run.
    async fn delete_internet_gateways(&self) -> Result<Vec<String>> {
        let mut errors = Vec::new();
        let mut igws: Vec<aws_sdk_ec2::types::InternetGateway> = Vec::new();
        let mut token: Option<String> = None;
        loop {
            let out = self
                .ec2
                .describe_internet_gateways()
                .filters(self.tag_filter())
                .set_next_token(token.clone())
                .send()
                .await
                .context("describe internet gateways")?;
            igws.extend(out.internet_gateways().iter().cloned());
            token = out.next_token().map(String::from);
            if token.is_none() {
                break;
            }
        }
        for igw in igws {
            let gid = match igw.internet_gateway_id() {
                Some(id) => id,
                None => continue,
            };
            for att in igw.attachments() {
                if let Some(vpc_id) = att.vpc_id() {
                    handle(
                        &mut errors,
                        &format!("detach IGW {gid} from {vpc_id}"),
                        self.ec2
                            .detach_internet_gateway()
                            .internet_gateway_id(gid)
                            .vpc_id(vpc_id)
                            .send()
                            .await,
                    );
                }
            }
            handle(
                &mut errors,
                &format!("internet gateway {gid}"),
                self.ec2
                    .delete_internet_gateway()
                    .internet_gateway_id(gid)
                    .send()
                    .await,
            );
        }
        Ok(errors)
    }

    /// Deletes the run's VPC(s).
    async fn delete_vpcs(&self) -> Result<Vec<String>> {
        let mut errors = Vec::new();
        for vpc_id in self.vpc_ids().await? {
            handle(
                &mut errors,
                &format!("VPC {vpc_id}"),
                self.ec2.delete_vpc().vpc_id(&vpc_id).send().await,
            );
        }
        Ok(errors)
    }

    /// The serial network teardown spine: ENIs → security groups → subnets →
    /// route tables → internet gateways → VPC.
    async fn network_branch(&self) -> Result<Vec<String>> {
        let mut errors = Vec::new();
        collect(&mut errors, self.delete_network_interfaces().await);
        collect(&mut errors, self.delete_security_groups().await);
        collect(&mut errors, self.delete_subnets().await);
        collect(&mut errors, self.delete_route_tables().await);
        collect(&mut errors, self.delete_internet_gateways().await);
        collect(&mut errors, self.delete_vpcs().await);
        Ok(errors)
    }

    // == IAM (global; matched by tag) ======================================

    async fn delete_iam(&self) -> Result<Vec<String>> {
        let mut errors = Vec::new();
        collect(&mut errors, self.delete_iam_instance_profiles().await);
        collect(&mut errors, self.delete_iam_roles().await);
        // After roles: deleting a role only detaches its policies, so the
        // customer-managed policy objects themselves must be deleted separately.
        collect(&mut errors, self.delete_iam_policies().await);
        collect(&mut errors, self.delete_iam_oidc_providers().await);
        Ok(errors)
    }

    async fn delete_iam_instance_profiles(&self) -> Result<Vec<String>> {
        let mut errors = Vec::new();
        let mut marker: Option<String> = None;
        loop {
            let out = self
                .iam
                .list_instance_profiles()
                .set_marker(marker.clone())
                .send()
                .await
                .context("list instance profiles")?;
            for ip in out.instance_profiles() {
                let name = ip.instance_profile_name();
                // On a tag-read failure, fall through to the name-prefix check
                // below rather than abort: Karpenter profiles are matchable by
                // name even when their tags can't be read.
                let tag_match = match self
                    .iam
                    .list_instance_profile_tags()
                    .instance_profile_name(name)
                    .send()
                    .await
                {
                    Ok(t) => t
                        .tags()
                        .iter()
                        .any(|t| t.key() == "TestRun" && t.value() == self.run_id),
                    Err(e) => {
                        errors.push(format!("list tags of instance profile {name}: {e}"));
                        false
                    }
                };
                // Karpenter-created instance profiles may carry the cluster tag
                // rather than TestRun; the run id is also embedded in the name.
                if !tag_match && !name.starts_with(&self.run_id) {
                    continue;
                }
                for role in ip.roles() {
                    handle(
                        &mut errors,
                        &format!(
                            "remove role {} from instance profile {name}",
                            role.role_name()
                        ),
                        self.iam
                            .remove_role_from_instance_profile()
                            .instance_profile_name(name)
                            .role_name(role.role_name())
                            .send()
                            .await,
                    );
                }
                handle(
                    &mut errors,
                    &format!("instance profile {name}"),
                    self.iam
                        .delete_instance_profile()
                        .instance_profile_name(name)
                        .send()
                        .await,
                );
            }
            marker = out.marker().map(String::from);
            if marker.is_none() {
                break;
            }
        }
        Ok(errors)
    }

    /// Names of IAM roles tagged for this run. IAM exposes no server-side tag
    /// filter, so this lists every role and reads each one's tags (an N+1 fan-out
    /// over the account's roles). Shared by the role delete and the completion
    /// check in [`Self::remaining`].
    async fn tagged_role_names(&self) -> Result<Vec<String>> {
        let mut names = Vec::new();
        let mut marker: Option<String> = None;
        loop {
            let out = self
                .iam
                .list_roles()
                .set_marker(marker.clone())
                .send()
                .await
                .context("list roles")?;
            for role in out.roles() {
                let name = role.role_name();
                // Per-role tag read keyed on a specific role name, so unlike the
                // filtered `list_roles` above it can 404 if the role was deleted
                // mid-enumeration (a prior pass, or a race). A role whose tags we
                // can't read can't match this run anyway, so skip it rather than
                // abort the whole listing.
                let Ok(tags) = self.iam.list_role_tags().role_name(name).send().await else {
                    continue;
                };
                if tags
                    .tags()
                    .iter()
                    .any(|t| t.key() == "TestRun" && t.value() == self.run_id)
                {
                    names.push(name.to_string());
                }
            }
            marker = out.marker().map(String::from);
            if marker.is_none() {
                break;
            }
        }
        Ok(names)
    }

    async fn delete_iam_roles(&self) -> Result<Vec<String>> {
        let mut errors = Vec::new();
        for name in self.tagged_role_names().await? {
            self.purge_role(&name, &mut errors).await;
        }
        Ok(errors)
    }

    /// Detaches policies, removes inline policies and instance-profile
    /// memberships, then deletes the role.
    async fn purge_role(&self, name: &str, errors: &mut Vec<String>) {
        match self
            .iam
            .list_attached_role_policies()
            .role_name(name)
            .send()
            .await
        {
            Ok(out) => {
                for pol in out.attached_policies() {
                    if let Some(arn) = pol.policy_arn() {
                        handle(
                            errors,
                            &format!("detach policy {arn} from role {name}"),
                            self.iam
                                .detach_role_policy()
                                .role_name(name)
                                .policy_arn(arn)
                                .send()
                                .await,
                        );
                    }
                }
            }
            Err(e) if !is_gone(e.code().unwrap_or_default()) => {
                errors.push(format!("list attached policies of {name}: {e}"));
            }
            Err(_) => {}
        }
        match self.iam.list_role_policies().role_name(name).send().await {
            Ok(out) => {
                for pol_name in out.policy_names() {
                    handle(
                        errors,
                        &format!("inline policy {pol_name} of role {name}"),
                        self.iam
                            .delete_role_policy()
                            .role_name(name)
                            .policy_name(pol_name)
                            .send()
                            .await,
                    );
                }
            }
            Err(e) if !is_gone(e.code().unwrap_or_default()) => {
                errors.push(format!("list inline policies of {name}: {e}"));
            }
            Err(_) => {}
        }
        match self
            .iam
            .list_instance_profiles_for_role()
            .role_name(name)
            .send()
            .await
        {
            Ok(out) => {
                for ip in out.instance_profiles() {
                    handle(
                        errors,
                        &format!(
                            "remove role {name} from instance profile {}",
                            ip.instance_profile_name()
                        ),
                        self.iam
                            .remove_role_from_instance_profile()
                            .instance_profile_name(ip.instance_profile_name())
                            .role_name(name)
                            .send()
                            .await,
                    );
                }
            }
            Err(e) if !is_gone(e.code().unwrap_or_default()) => {
                errors.push(format!("list instance profiles for {name}: {e}"));
            }
            Err(_) => {}
        }
        handle(
            errors,
            &format!("IAM role {name}"),
            self.iam.delete_role().role_name(name).send().await,
        );
    }

    /// ARNs of customer-managed (`Scope=Local`) IAM policies belonging to this
    /// run. Matched by `TestRun` tag, falling back to the run-id name prefix (the
    /// policies are named `<run>-albc`, `<run>-karpenter-controller`, etc.) when
    /// tags cannot be read. Shared by the delete and the completion check in
    /// [`Self::remaining`].
    async fn tagged_local_policy_arns(&self) -> Result<Vec<String>> {
        let mut arns = Vec::new();
        let mut marker: Option<String> = None;
        loop {
            let out = self
                .iam
                .list_policies()
                .scope(aws_sdk_iam::types::PolicyScopeType::Local)
                .set_marker(marker.clone())
                .send()
                .await
                .context("list policies")?;
            for pol in out.policies() {
                let arn = match pol.arn() {
                    Some(a) => a,
                    None => continue,
                };
                let name_match = pol
                    .policy_name()
                    .is_some_and(|n| n.starts_with(&self.run_id));
                let tag_match = match self.iam.list_policy_tags().policy_arn(arn).send().await {
                    Ok(t) => t
                        .tags()
                        .iter()
                        .any(|t| t.key() == "TestRun" && t.value() == self.run_id),
                    Err(_) => false,
                };
                if name_match || tag_match {
                    arns.push(arn.to_string());
                }
            }
            marker = out.marker().map(String::from);
            if marker.is_none() {
                break;
            }
        }
        Ok(arns)
    }

    async fn delete_iam_policies(&self) -> Result<Vec<String>> {
        let mut errors = Vec::new();
        for arn in self.tagged_local_policy_arns().await? {
            self.purge_policy(&arn, &mut errors).await;
        }
        Ok(errors)
    }

    /// Detaches a customer-managed policy from every entity, deletes its
    /// non-default versions, then deletes the policy. A policy cannot be deleted
    /// while still attached or while non-default versions exist.
    async fn purge_policy(&self, arn: &str, errors: &mut Vec<String>) {
        match self
            .iam
            .list_entities_for_policy()
            .policy_arn(arn)
            .send()
            .await
        {
            Ok(out) => {
                for role in out.policy_roles() {
                    if let Some(name) = role.role_name() {
                        handle(
                            errors,
                            &format!("detach policy {arn} from role {name}"),
                            self.iam
                                .detach_role_policy()
                                .role_name(name)
                                .policy_arn(arn)
                                .send()
                                .await,
                        );
                    }
                }
                for user in out.policy_users() {
                    if let Some(name) = user.user_name() {
                        handle(
                            errors,
                            &format!("detach policy {arn} from user {name}"),
                            self.iam
                                .detach_user_policy()
                                .user_name(name)
                                .policy_arn(arn)
                                .send()
                                .await,
                        );
                    }
                }
                for group in out.policy_groups() {
                    if let Some(name) = group.group_name() {
                        handle(
                            errors,
                            &format!("detach policy {arn} from group {name}"),
                            self.iam
                                .detach_group_policy()
                                .group_name(name)
                                .policy_arn(arn)
                                .send()
                                .await,
                        );
                    }
                }
            }
            Err(e) if !is_gone(e.code().unwrap_or_default()) => {
                errors.push(format!("list entities for policy {arn}: {e}"));
            }
            Err(_) => {}
        }
        match self.iam.list_policy_versions().policy_arn(arn).send().await {
            Ok(out) => {
                for v in out.versions() {
                    if v.is_default_version() {
                        continue;
                    }
                    if let Some(vid) = v.version_id() {
                        handle(
                            errors,
                            &format!("policy version {vid} of {arn}"),
                            self.iam
                                .delete_policy_version()
                                .policy_arn(arn)
                                .version_id(vid)
                                .send()
                                .await,
                        );
                    }
                }
            }
            Err(e) if !is_gone(e.code().unwrap_or_default()) => {
                errors.push(format!("list versions of policy {arn}: {e}"));
            }
            Err(_) => {}
        }
        handle(
            errors,
            &format!("IAM policy {arn}"),
            self.iam.delete_policy().policy_arn(arn).send().await,
        );
    }

    async fn delete_iam_oidc_providers(&self) -> Result<Vec<String>> {
        let mut errors = Vec::new();
        let out = self
            .iam
            .list_open_id_connect_providers()
            .send()
            .await
            .context("list oidc providers")?;
        for p in out.open_id_connect_provider_list() {
            let arn = match p.arn() {
                Some(a) => a,
                None => continue,
            };
            // Per-provider tag read: on failure, skip this one rather than abort.
            let tag_match = match self
                .iam
                .list_open_id_connect_provider_tags()
                .open_id_connect_provider_arn(arn)
                .send()
                .await
            {
                Ok(t) => t
                    .tags()
                    .iter()
                    .any(|t| t.key() == "TestRun" && t.value() == self.run_id),
                Err(e) => {
                    errors.push(format!("list tags of oidc provider {arn}: {e}"));
                    false
                }
            };
            if !tag_match {
                continue;
            }
            handle(
                &mut errors,
                &format!("OIDC provider {arn}"),
                self.iam
                    .delete_open_id_connect_provider()
                    .open_id_connect_provider_arn(arn)
                    .send()
                    .await,
            );
        }
        Ok(errors)
    }

    // == orchestration =====================================================

    /// Runs one ordered deletion pass as the dependency DAG (see the module
    /// docs). Returns the errors collected across all branches.
    async fn sweep_once(&self) -> Vec<String> {
        // Stage 1: all branches that gate the network teardown, plus the fully
        // independent ones, run concurrently. The blocking waits inside the
        // compute/RDS/NAT branches form the barrier.
        let (compute, rds, nat, lbs, vpce, s3, karpenter, kms) = tokio::join!(
            self.compute_branch(),
            self.rds_branch(),
            self.nat_branch(),
            self.delete_load_balancers(),
            self.delete_vpc_endpoints(),
            self.delete_buckets(),
            self.karpenter_branch(),
            self.kms_branch(),
        );
        let mut errors = Vec::new();
        for branch in [compute, rds, nat, lbs, vpce, s3, karpenter, kms] {
            collect(&mut errors, branch);
        }

        // Stage 2: the serial network spine, concurrent with IAM (which is
        // global and only needed the cluster/instances — gone above — removed).
        let (network, iam) = tokio::join!(self.network_branch(), self.delete_iam());
        collect(&mut errors, network);
        collect(&mut errors, iam);
        errors
    }

    /// Re-queries the main resource types and returns identifiers of anything
    /// still present. Uses strongly-consistent service describes (no eventually
    /// consistent tagging API), so a clean result is trustworthy.
    async fn remaining(&self) -> Vec<String> {
        let mut out = Vec::new();

        if let Ok(ids) = self.live_instance_ids().await {
            for id in ids {
                out.push(format!("ec2 instance {id}"));
            }
        }

        if let Ok(r) = self.eks.describe_cluster().name(&self.cluster).send().await
            && r.cluster().is_some()
        {
            out.push(format!("eks cluster {}", self.cluster));
        }

        // The VPC stands in for everything that lives inside it: a surviving RDS
        // instance, NAT gateway, load balancer, subnet, route table, or security
        // group blocks its dependents and ultimately the VPC delete, so a leak of
        // any of those keeps the VPC present and is reported here. We therefore do
        // not re-query those types individually.
        if let Ok(ids) = self.vpc_ids().await {
            for id in ids {
                out.push(format!("vpc {id}"));
            }
        }

        if let Ok(names) = self.list_all_buckets().await {
            for name in names {
                match self.s3.get_bucket_tagging().bucket(&name).send().await {
                    Ok(t) => {
                        if t.tag_set()
                            .iter()
                            .any(|t| t.key() == "TestRun" && t.value() == self.run_id)
                        {
                            out.push(format!("s3 bucket {name}"));
                        }
                    }
                    Err(e) => {
                        // Untagged/gone/other-region buckets are not ours. Any
                        // other error means we cannot prove the bucket is clean,
                        // so report it rather than risk a silent leak.
                        let code = e.code().unwrap_or_default();
                        if !is_gone(code)
                            && code != "PermanentRedirect"
                            && code != "AuthorizationHeaderMalformed"
                        {
                            out.push(format!("s3 bucket {name} (tag check failed: {code})"));
                        }
                    }
                }
            }
        }

        // IAM is global, so leaked roles sit in no VPC and are not caught by the
        // VPC proxy above; check them directly. (Instance profiles and OIDC
        // providers are not re-checked here — they share the run-id name prefix,
        // so a leak collides loudly rather than silently.)
        if let Ok(names) = self.tagged_role_names().await {
            for name in names {
                out.push(format!("iam role {name}"));
            }
        }
        if let Ok(arns) = self.tagged_local_policy_arns().await {
            for arn in arns {
                out.push(format!("iam policy {arn}"));
            }
        }

        // The compute branch deletes the cluster log group after waiting for the
        // cluster to drain (the control plane recreates it mid-drain). This is a
        // backstop: if a group is somehow still present, surface it so the sweep
        // doesn't declare success and a later pass can reclaim it.
        let prefix = format!("/aws/eks/{}/", self.cluster);
        if let Ok(o) = self
            .logs
            .describe_log_groups()
            .log_group_name_prefix(&prefix)
            .send()
            .await
        {
            for lg in o.log_groups() {
                if let Some(name) = lg.log_group_name() {
                    out.push(format!("log group {name}"));
                }
            }
        }

        // Karpenter interruption plumbing, the RDS parameter group, and the EKS
        // encryption key live outside the VPC, so they need explicit checks. A
        // KMS key already pending deletion is excluded by tagged_kms_key_ids.
        if let Ok(urls) = self.interruption_queue_urls().await {
            for url in urls {
                out.push(format!("sqs queue {url}"));
            }
        }
        if let Ok(names) = self.interruption_rule_names().await {
            for name in names {
                out.push(format!("eventbridge rule {name}"));
            }
        }
        if let Ok(names) = self.tagged_db_parameter_group_names().await {
            for name in names {
                out.push(format!("rds parameter group {name}"));
            }
        }
        if let Ok(ids) = self.tagged_kms_key_ids().await {
            for id in ids {
                out.push(format!("kms key {id}"));
            }
        }

        out
    }

    /// Sweeps until nothing remains or no further progress is made.
    async fn run(&self) -> Result<()> {
        println!(
            "Purging AWS resources for run {} in {} (cluster {})",
            self.run_id, self.region, self.cluster
        );
        for pass in 1..=MAX_PASSES {
            println!("-- pass {pass}/{MAX_PASSES} --");
            let errors = self.sweep_once().await;
            let remaining = self.remaining().await;
            if remaining.is_empty() && errors.is_empty() {
                println!("All resources for {} deleted.", self.run_id);
                return Ok(());
            }
            println!(
                "  After pass {pass}: {} resource(s) still present, {} error(s)",
                remaining.len(),
                errors.len()
            );
            // Let eventually-consistent deletes settle before re-sweeping. Skip
            // after the final pass — nothing sweeps again.
            if pass < MAX_PASSES {
                tokio::time::sleep(INTER_PASS_DELAY).await;
            }
        }

        let remaining = self.remaining().await;
        if remaining.is_empty() {
            println!("All resources for {} deleted.", self.run_id);
            return Ok(());
        }
        // GitHub Actions error annotation, matching the non-zero exit from the
        // `bail!` below. Slow deletes may still be draining; a follow-up purge
        // should finish the job.
        println!(
            "::error::Run {} ({}) still has {} resource(s) after {MAX_PASSES} passes. \
             A follow-up purge should reclaim them once slow deletes finish draining. \
             Remaining:",
            self.run_id,
            self.region,
            remaining.len()
        );
        for r in &remaining {
            println!("    {r}");
        }
        bail!(
            "purge left {} resource(s) for run {}",
            remaining.len(),
            self.run_id
        );
    }
}
