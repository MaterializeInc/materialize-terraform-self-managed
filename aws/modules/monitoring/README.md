## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0, < 5.101.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 2.5.0, < 2.18.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.10.0, < 2.39.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.0.0, < 3.10.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 5.0, < 5.101.0 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.0.0, < 3.10.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_grafana_database"></a> [grafana\_database](#module\_grafana\_database) | ../database | n/a |
| <a name="module_monitoring"></a> [monitoring](#module\_monitoring) | github.com/MaterializeInc/materialize-monitoring//terraform/modules/materialize-monitoring | materialize-monitoring/v0.13.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_role.telemetry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.telemetry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_s3_bucket.telemetry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.telemetry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_public_access_block.telemetry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.telemetry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.telemetry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [random_id.bucket_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |
| [random_password.grafana_database](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [aws_iam_policy_document.assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.bucket_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_additional_values"></a> [additional\_values](#input\_additional\_values) | Raw YAML documents appended to the Helm values, last, so they override everything the modules compute. | `list(string)` | `[]` | no |
| <a name="input_bucket_encryption_mode"></a> [bucket\_encryption\_mode](#input\_bucket\_encryption\_mode) | Server-side encryption for the telemetry buckets. SSE-S3 by default; SSE-KMS requires `bucket_kms_key_arn` and grants the two backend roles `kms:Decrypt` and `kms:GenerateDataKey` on that key. Matches the option `aws/modules/storage` offers for the Materialize persist bucket. | `string` | `"SSE-S3"` | no |
| <a name="input_bucket_force_destroy"></a> [bucket\_force\_destroy](#input\_bucket\_force\_destroy) | Allow Terraform to delete non-empty buckets. Leave false outside throwaway environments — destroying it takes the telemetry with it. | `bool` | `false` | no |
| <a name="input_bucket_kms_key_arn"></a> [bucket\_kms\_key\_arn](#input\_bucket\_kms\_key\_arn) | ARN of the KMS key to use when `bucket_encryption_mode` is SSE-KMS. A customer-managed key, not an alias — the IAM grant needs the ARN. Bucket Keys are enabled alongside it, because both backends write enough small objects for per-object KMS calls to show up on the bill. | `string` | `null` | no |
| <a name="input_chart_registry"></a> [chart\_registry](#input\_chart\_registry) | OCI registry holding the materialize-monitoring charts. Override for a mirrored or air-gapped registry; there is no way to reach this through `additional_values`. | `string` | `null` | no |
| <a name="input_chart_version"></a> [chart\_version](#input\_chart\_version) | Override the materialize-monitoring chart version. Leave null to use the version the pinned module ships with — the two are one release. | `string` | `null` | no |
| <a name="input_cluster_oidc_issuer_url"></a> [cluster\_oidc\_issuer\_url](#input\_cluster\_oidc\_issuer\_url) | OIDC issuer URL of the cluster, from the EKS module. | `string` | n/a | yes |
| <a name="input_create_namespace"></a> [create\_namespace](#input\_create\_namespace) | Whether the monitoring module creates the namespace. False by default because the operator module already creates `monitoring`. | `bool` | `false` | no |
| <a name="input_enable_bucket_versioning"></a> [enable\_bucket\_versioning](#input\_enable\_bucket\_versioning) | Enable versioning on the telemetry buckets. Versioning is the disaster-recovery primitive for both Loki and Thanos, neither of which has a native snapshot. | `bool` | `true` | no |
| <a name="input_enable_monitoring_crds"></a> [enable\_monitoring\_crds](#input\_enable\_monitoring\_crds) | Install the materialize-monitoring-crds chart (prometheus-operator and grafana-operator CRDs). Set false when the cluster already has them from elsewhere, such as kube-prometheus-stack or a platform team that owns CRDs centrally. Null uses the monitoring module's default. | `bool` | `null` | no |
| <a name="input_grafana_admin_password"></a> [grafana\_admin\_password](#input\_grafana\_admin\_password) | Grafana admin password. Generated when null. | `string` | `null` | no |
| <a name="input_grafana_database"></a> [grafana\_database](#input\_grafana\_database) | Provision a dedicated RDS PostgreSQL instance for Grafana's own state.<br/><br/>Grafana keeps users, service accounts and tokens, annotations, dashboard versions and<br/>permissions, preferences, and alert-rule state in a database separate from the observability<br/>data in Loki and Thanos. The chart default is SQLite on an `emptyDir`, so all of it is lost on<br/>every restart, upgrade, and reschedule. That is tolerable while Grafana is reached through<br/>`port-forward` and not once it is exposed, which is why this and `grafana_ingress` belong in<br/>the same change.<br/><br/>Dedicated rather than a database inside the Materialize RDS instance, deliberately: RDS has no<br/>API for creating a second database in an existing instance, so sharing one would need the<br/>PostgreSQL provider to reach a private endpoint from wherever Terraform runs. A separate<br/>instance also keeps Grafana's blast radius away from Materialize's metadata.<br/><br/>`db.t4g.micro` is enough. Grafana's state is small and its query rate is a handful per page<br/>load; this is a durability decision, not a capacity one.<br/><br/>Null leaves Grafana on SQLite. Point at a database you already run with the<br/>`grafana_database_*` variables instead. | <pre>object({<br/>    vpc_id                    = string<br/>    subnet_ids                = list(string)<br/>    cluster_name              = string<br/>    cluster_security_group_id = string<br/>    node_security_group_id    = string<br/><br/>    instance_class          = optional(string, "db.t4g.micro")<br/>    postgres_version        = optional(string, "16")<br/>    allocated_storage       = optional(number, 20)<br/>    max_allocated_storage   = optional(number, 100)<br/>    multi_az                = optional(bool, false)<br/>    backup_retention_period = optional(number, 7)<br/>    kms_key_id              = optional(string, null)<br/>    create_kms_key          = optional(bool, true)<br/>    skip_final_snapshot     = optional(bool, false)<br/>  })</pre> | `null` | no |
| <a name="input_grafana_database_host"></a> [grafana\_database\_host](#input\_grafana\_database\_host) | Hostname of an existing PostgreSQL database for Grafana's state. Mutually exclusive with `grafana_database`. Host only — the port is `grafana_database_port`. | `string` | `null` | no |
| <a name="input_grafana_database_name"></a> [grafana\_database\_name](#input\_grafana\_database\_name) | Name of the database Grafana owns. | `string` | `"grafana"` | no |
| <a name="input_grafana_database_password"></a> [grafana\_database\_password](#input\_grafana\_database\_password) | Password for `grafana_database_user`. Generated when this module creates the instance. Null with an external host means the connection needs no password. | `string` | `null` | no |
| <a name="input_grafana_database_port"></a> [grafana\_database\_port](#input\_grafana\_database\_port) | Port for `grafana_database_host`. | `number` | `5432` | no |
| <a name="input_grafana_database_ssl_mode"></a> [grafana\_database\_ssl\_mode](#input\_grafana\_database\_ssl\_mode) | libpq SSL mode for the Grafana database connection. `require` encrypts but does not authenticate the server; `verify-full` also authenticates it but needs the RDS CA bundle mounted, which this module does not do — supply `grafana.ini.database.ca_cert_path` and the matching mount through `additional_values` for that. | `string` | `"require"` | no |
| <a name="input_grafana_database_user"></a> [grafana\_database\_user](#input\_grafana\_database\_user) | Database user Grafana connects as. Must own `grafana_database_name`: Grafana runs schema migrations at startup, so a read/write-only grant fails them. | `string` | `"grafana"` | no |
| <a name="input_grafana_ingress"></a> [grafana\_ingress](#input\_grafana\_ingress) | Expose Grafana through an ALB, provisioned by the AWS Load Balancer Controller from an<br/>Ingress the chart renders.<br/><br/>Ingress rather than this repo's `nlb` module: Grafana is ordinary HTTP wanting host-based<br/>routing and a certificate, which is what the controller builds an ALB for. The `nlb` module<br/>exists for the Materialize console, whose OIDC redirect and port constraints pushed it onto<br/>443 with a target group; none of that applies here. The controller must already be installed —<br/>the examples install it as `module.aws_lbc`.<br/><br/>Internal by default, and public requires an allowlist that is *enforced* rather than merely<br/>defaulted, matching the `nlb` module. `ingress_cidr_blocks` becomes<br/>`alb.ingress.kubernetes.io/inbound-cidrs`; on an internal load balancer pass your VPC CIDR.<br/><br/>Set `certificate_arn` unless TLS is terminated somewhere else. Grafana authenticates with a<br/>session cookie, so without TLS that cookie and the admin password cross the network in the<br/>clear, and the chart warns about exactly that.<br/><br/>DNS for `host` is yours to create — neither the Ingress nor the controller publishes it.<br/><br/>Null leaves Grafana on a ClusterIP Service, reachable only with `kubectl port-forward`. | <pre>object({<br/>    host = string<br/><br/>    internal            = optional(bool, true)<br/>    ingress_cidr_blocks = optional(list(string), null)<br/>    certificate_arn     = optional(string, null)<br/>    ingress_class_name  = optional(string, "alb")<br/>    subnet_ids          = optional(list(string), null)<br/>    annotations         = optional(map(string), {})<br/>  })</pre> | `null` | no |
| <a name="input_iam_permissions_boundary"></a> [iam\_permissions\_boundary](#input\_iam\_permissions\_boundary) | Optional permissions boundary applied to the IAM roles this module creates. No other AWS module in this repository takes one yet; the intent is that they should, and this is the first. Leaving it null keeps the previous behaviour, so adding it elsewhere later is additive. | `string` | `null` | no |
| <a name="input_install_metrics_server"></a> [install\_metrics\_server](#input\_install\_metrics\_server) | Install metrics-server as part of the monitoring stack. Set true when the operator module has `install_metrics_server = false`, or the Materialize Console loses cluster metrics. | `bool` | `false` | no |
| <a name="input_install_timeout"></a> [install\_timeout](#input\_install\_timeout) | Timeout for each Helm release, in seconds. Null uses the monitoring module's default, which is well above Helm's 300s because a first install brings up Loki, Thanos, Grafana, and both Alloy roles together. | `number` | `null` | no |
| <a name="input_logs_retention_days"></a> [logs\_retention\_days](#input\_logs\_retention\_days) | Expire Loki objects after this many days. Null disables the lifecycle rule and leaves retention entirely to Loki's compactor. | `number` | `null` | no |
| <a name="input_materialize_instance_namespace"></a> [materialize\_instance\_namespace](#input\_materialize\_instance\_namespace) | Namespace the Materialize instance runs in. | `string` | `"materialize-environment"` | no |
| <a name="input_materialize_operator_namespace"></a> [materialize\_operator\_namespace](#input\_materialize\_operator\_namespace) | Namespace the Materialize operator runs in. | `string` | `"materialize"` | no |
| <a name="input_metrics_retention_days"></a> [metrics\_retention\_days](#input\_metrics\_retention\_days) | Expire Thanos objects after this many days. Null disables the lifecycle rule.<br/><br/>Leave it null unless you know what you are doing: Thanos's compactor already enforces<br/>retention per downsampling resolution (raw / 5m / 1h), and a bucket rule that expires<br/>sooner deletes blocks the compactor still expects to find. | `number` | `null` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix for the bucket and IAM role names this module creates. Capped at 40 characters so the longest generated name still fits: S3 bucket names are limited to 63, and `-mzmon-metrics-` plus the 8-character random suffix takes 23. | `string` | n/a | yes |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace the monitoring stack is installed into. Also the namespace half of every IRSA trust-policy subject. | `string` | `"monitoring"` | no |
| <a name="input_node_selector"></a> [node\_selector](#input\_node\_selector) | Node selector for the centralized monitoring workloads. Not applied to the Alloy agent DaemonSet, which must reach every node. | `map(string)` | `{}` | no |
| <a name="input_oidc_provider_arn"></a> [oidc\_provider\_arn](#input\_oidc\_provider\_arn) | ARN of the cluster's IAM OIDC provider, from the EKS module. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region the buckets live in. Passed explicitly rather than read from a data source, matching the rest of this repository. | `string` | n/a | yes |
| <a name="input_sizing"></a> [sizing](#input\_sizing) | Deployment size: small, medium, or large. The chart's defaults are medium. | `string` | `"medium"` | no |
| <a name="input_storage_class"></a> [storage\_class](#input\_storage\_class) | StorageClass for the PVC-backed monitoring workloads (Alertmanager, the Loki ruler, and Thanos receive/compactor/store-gateway). Null uses whatever class the cluster marks default; the examples pass the `gp3` class from the `ebs-csi-driver` module. | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the resources this module creates. | `map(string)` | `{}` | no |
| <a name="input_tolerations"></a> [tolerations](#input\_tolerations) | Tolerations for the monitoring workloads, including the Alloy agent DaemonSet. | <pre>list(object({<br/>    key      = optional(string)<br/>    operator = optional(string, "Equal")<br/>    value    = optional(string)<br/>    effect   = optional(string)<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_grafana_admin_password"></a> [grafana\_admin\_password](#output\_grafana\_admin\_password) | Grafana admin password. |
| <a name="output_grafana_database_endpoint"></a> [grafana\_database\_endpoint](#output\_grafana\_database\_endpoint) | `host:port` of the database backing Grafana's state, or null when Grafana is on SQLite. |
| <a name="output_grafana_database_password"></a> [grafana\_database\_password](#output\_grafana\_database\_password) | Password for the Grafana database user. Generated when this module creates the instance. |
| <a name="output_grafana_url"></a> [grafana\_url](#output\_grafana\_url) | URL for Grafana: the external one when `grafana_ingress` is set, the in-cluster Service otherwise — in which case reaching it means a port-forward. DNS for an external host is yours to create; nothing here publishes it. |
| <a name="output_iam_role_arns"></a> [iam\_role\_arns](#output\_iam\_role\_arns) | IRSA role ARNs, by backend. |
| <a name="output_logs_bucket"></a> [logs\_bucket](#output\_logs\_bucket) | S3 bucket holding Loki chunks and the ruler's state. |
| <a name="output_logs_url"></a> [logs\_url](#output\_logs\_url) | Loki read endpoint. |
| <a name="output_metrics_bucket"></a> [metrics\_bucket](#output\_metrics\_bucket) | S3 bucket holding Thanos blocks. |
| <a name="output_metrics_url"></a> [metrics\_url](#output\_metrics\_url) | Thanos Query endpoint. Prometheus-API-compatible. |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace the monitoring stack is installed into. |
| <a name="output_workload_identity_subjects"></a> [workload\_identity\_subjects](#output\_workload\_identity\_subjects) | Service-account subjects the IRSA trust policies are scoped to. Emitted by the monitoring module from the names the chart actually renders, so a mismatch with the roles above is visible rather than silent. |
