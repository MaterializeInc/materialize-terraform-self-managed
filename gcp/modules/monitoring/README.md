## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 7.22, < 8 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 2.5.0, < 2.18.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.10.0, < 2.39.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.0.0, < 3.10.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_google"></a> [google](#provider\_google) | >= 7.22, < 8 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.0.0, < 3.10.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_grafana_database"></a> [grafana\_database](#module\_grafana\_database) | ../database | n/a |
| <a name="module_monitoring"></a> [monitoring](#module\_monitoring) | github.com/MaterializeInc/materialize-monitoring//terraform/modules/materialize-monitoring | materialize-monitoring/v0.13.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [google_project_iam_member.gateway_metric_writer](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_service_account.gateway](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_service_account.telemetry](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_service_account_iam_member.gateway_workload_identity](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_member) | resource |
| [google_service_account_iam_member.workload_identity](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_member) | resource |
| [google_storage_bucket.telemetry](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket) | resource |
| [google_storage_bucket_iam_member.telemetry](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_iam_member) | resource |
| [random_password.grafana_database](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_additional_values"></a> [additional\_values](#input\_additional\_values) | Raw YAML documents appended to the Helm values, last, so they override everything the modules compute. | `list(string)` | `[]` | no |
| <a name="input_bucket_force_destroy"></a> [bucket\_force\_destroy](#input\_bucket\_force\_destroy) | Allow Terraform to delete non-empty buckets. Leave false outside throwaway environments — destroying it takes the telemetry with it. | `bool` | `false` | no |
| <a name="input_chart_registry"></a> [chart\_registry](#input\_chart\_registry) | OCI registry holding the materialize-monitoring charts. Override for a mirrored or air-gapped registry; there is no way to reach this through `additional_values`. | `string` | `null` | no |
| <a name="input_chart_version"></a> [chart\_version](#input\_chart\_version) | Override the materialize-monitoring chart version. Leave null to use the version the pinned module ships with — the two are one release. | `string` | `null` | no |
| <a name="input_create_namespace"></a> [create\_namespace](#input\_create\_namespace) | Whether the monitoring module creates the namespace. False by default because the operator module already creates `monitoring`. | `bool` | `false` | no |
| <a name="input_enable_bucket_versioning"></a> [enable\_bucket\_versioning](#input\_enable\_bucket\_versioning) | Enable versioning on the telemetry buckets. Versioning is the disaster-recovery primitive for both Loki and Thanos, neither of which has a native snapshot. | `bool` | `true` | no |
| <a name="input_enable_google_cloud_metrics"></a> [enable\_google\_cloud\_metrics](#input\_enable\_google\_cloud\_metrics) | Also export metrics to Google Cloud Monitoring from the Alloy gateway. Thanos is unaffected.<br/><br/>Creates a service account with `roles/monitoring.metricWriter` (write-only) and binds the<br/>gateway's in-cluster ServiceAccount to it via Workload Identity. | `bool` | `false` | no |
| <a name="input_enable_monitoring_crds"></a> [enable\_monitoring\_crds](#input\_enable\_monitoring\_crds) | Install the materialize-monitoring-crds chart (prometheus-operator and grafana-operator CRDs). Set false when the cluster already has them from elsewhere, such as kube-prometheus-stack or a platform team that owns CRDs centrally. Null uses the monitoring module's default. | `bool` | `null` | no |
| <a name="input_google_cloud_metrics_min_importance"></a> [google\_cloud\_metrics\_min\_importance](#input\_google\_cloud\_metrics\_min\_importance) | Metric tier to export: `essential`, `recommended`, `extended`, `diagnostic`, or `all`. Each tier includes the ones below it. A cost control — Cloud Monitoring bills per custom metric. | `string` | `"recommended"` | no |
| <a name="input_google_cloud_metrics_prefix"></a> [google\_cloud\_metrics\_prefix](#input\_google\_cloud\_metrics\_prefix) | Metric name prefix in Cloud Monitoring. Null uses the chart's default (`workload.googleapis.com/mzmon`). | `string` | `null` | no |
| <a name="input_grafana_admin_password"></a> [grafana\_admin\_password](#input\_grafana\_admin\_password) | Grafana admin password. Generated when null. | `string` | `null` | no |
| <a name="input_grafana_database"></a> [grafana\_database](#input\_grafana\_database) | Provision a dedicated Cloud SQL PostgreSQL instance for Grafana's own state.<br/><br/>Grafana keeps users, service accounts and tokens, annotations, dashboard versions and<br/>permissions, preferences, and alert-rule state in a database separate from the observability<br/>data in Loki and Thanos. The chart default is SQLite on an `emptyDir`, so all of it is lost on<br/>every restart, upgrade, and reschedule. That is tolerable while Grafana is reached through<br/>`port-forward` and not once it is exposed, which is why this and `grafana_load_balancer`<br/>belong in the same change.<br/><br/>Dedicated rather than a database inside the Materialize instance: it keeps Grafana's blast<br/>radius away from Materialize's metadata, and it is the same shape the AWS and Azure wrappers<br/>use, where sharing is not cleanly possible at all.<br/><br/>`db-f1-micro` is enough. Grafana's state is small and its query rate is a handful per page<br/>load; this is a durability decision, not a capacity one.<br/><br/>Null leaves Grafana on SQLite. Point at a database you already run with the<br/>`grafana_database_*` variables instead. | <pre>object({<br/>    network_id = string<br/><br/>    tier                           = optional(string, "db-f1-micro")<br/>    db_version                     = optional(string, "POSTGRES_16")<br/>    edition                        = optional(string, "ENTERPRISE")<br/>    disk_size                      = optional(number, 10)<br/>    backup_enabled                 = optional(bool, true)<br/>    point_in_time_recovery_enabled = optional(bool, false)<br/>  })</pre> | `null` | no |
| <a name="input_grafana_database_host"></a> [grafana\_database\_host](#input\_grafana\_database\_host) | Hostname or IP of an existing PostgreSQL database for Grafana's state. Mutually exclusive with `grafana_database`. Host only — the port is `grafana_database_port`. | `string` | `null` | no |
| <a name="input_grafana_database_name"></a> [grafana\_database\_name](#input\_grafana\_database\_name) | Name of the database Grafana owns. | `string` | `"grafana"` | no |
| <a name="input_grafana_database_password"></a> [grafana\_database\_password](#input\_grafana\_database\_password) | Password for `grafana_database_user`. Generated when this module creates the instance. Null with an external host means the connection needs no password — the Cloud SQL Auth Proxy sidecar shape. | `string` | `null` | no |
| <a name="input_grafana_database_port"></a> [grafana\_database\_port](#input\_grafana\_database\_port) | Port for `grafana_database_host`. | `number` | `5432` | no |
| <a name="input_grafana_database_ssl_mode"></a> [grafana\_database\_ssl\_mode](#input\_grafana\_database\_ssl\_mode) | libpq SSL mode for the Grafana database connection. `require` encrypts but does not authenticate the server; `verify-full` also authenticates it but needs the instance's server CA mounted, which this module does not do — supply `grafana.ini.database.ca_cert_path` and the matching mount through `additional_values` for that. | `string` | `"require"` | no |
| <a name="input_grafana_database_user"></a> [grafana\_database\_user](#input\_grafana\_database\_user) | Database user Grafana connects as. Must be able to create objects in `grafana_database_name`: Grafana runs schema migrations at startup, so a read/write-only grant fails them. A Cloud SQL user created through the API gets `cloudsqlsuperuser`, which satisfies this. | `string` | `"grafana"` | no |
| <a name="input_grafana_load_balancer"></a> [grafana\_load\_balancer](#input\_grafana\_load\_balancer) | Expose Grafana through a GCP load balancer, provisioned from the `LoadBalancer` Service the<br/>chart renders.<br/><br/>A Service rather than an Ingress: this is the shape GKE takes without an ingress controller<br/>installed, and it matches what the `load_balancers` module already does for the Materialize<br/>console. The two are not an L7-versus-L4 choice — both ask GCP for a load balancer — so pick<br/>by what the cluster's controllers actually consume.<br/><br/>Internal by default, and `ingress_cidr_blocks` is required rather than defaulted: it becomes<br/>`loadBalancerSourceRanges` on the Service, and the chart refuses to render a `LoadBalancer`<br/>with no allowlist. On an internal load balancer pass your VPC CIDR; the chart cannot see the<br/>`Internal` annotation, so the allowlist is what makes the intent legible to it.<br/><br/>`host` is optional because a GCP load balancer answers on an IP. Set it once DNS exists —<br/>Grafana builds share links, alert notification links, and OAuth redirect URIs from<br/>`root_url`, and the chart warns while it is unset.<br/><br/>Null leaves Grafana on a ClusterIP Service, reachable only with `kubectl port-forward`. | <pre>object({<br/>    ingress_cidr_blocks = list(string)<br/><br/>    internal    = optional(bool, true)<br/>    host        = optional(string, null)<br/>    tls         = optional(bool, false)<br/>    annotations = optional(map(string), {})<br/>  })</pre> | `null` | no |
| <a name="input_install_metrics_server"></a> [install\_metrics\_server](#input\_install\_metrics\_server) | Install metrics-server as part of the monitoring stack. Set true when the operator module has `install_metrics_server = false`, or the Materialize Console loses cluster metrics. | `bool` | `false` | no |
| <a name="input_install_timeout"></a> [install\_timeout](#input\_install\_timeout) | Timeout for each Helm release, in seconds. Null uses the monitoring module's default, which is well above Helm's 300s because a first install brings up Loki, Thanos, Grafana, and both Alloy roles together. | `number` | `null` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels applied to the buckets this module creates. | `map(string)` | `{}` | no |
| <a name="input_logs_retention_days"></a> [logs\_retention\_days](#input\_logs\_retention\_days) | Delete Loki objects after this many days. Null disables the lifecycle rule and leaves retention to Loki's compactor. | `number` | `null` | no |
| <a name="input_materialize_instance_namespace"></a> [materialize\_instance\_namespace](#input\_materialize\_instance\_namespace) | Namespace the Materialize instance runs in. | `string` | `"materialize-environment"` | no |
| <a name="input_materialize_operator_namespace"></a> [materialize\_operator\_namespace](#input\_materialize\_operator\_namespace) | Namespace the Materialize operator runs in. | `string` | `"materialize"` | no |
| <a name="input_metrics_retention_days"></a> [metrics\_retention\_days](#input\_metrics\_retention\_days) | Delete Thanos objects after this many days. Null disables the lifecycle rule.<br/><br/>Leave it null unless you know what you are doing: Thanos's compactor already enforces<br/>retention per downsampling resolution (raw / 5m / 1h), and a bucket rule that deletes<br/>sooner removes blocks the compactor still expects to find. | `number` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace the monitoring stack is installed into. Also the namespace half of every Workload Identity member. | `string` | `"monitoring"` | no |
| <a name="input_node_selector"></a> [node\_selector](#input\_node\_selector) | Node selector for the centralized monitoring workloads. Not applied to the Alloy agent DaemonSet, which must reach every node. | `map(string)` | `{}` | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefix for the bucket and service-account names this module creates. Capped at 17 characters so the longest generated name still fits: a service account `account_id` is limited to 30, and `-mzmon-thanos` takes 13 of them. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | GCP project holding the buckets and service accounts. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | Location for the telemetry buckets. | `string` | n/a | yes |
| <a name="input_sizing"></a> [sizing](#input\_sizing) | Deployment size: small, medium, or large. The chart's defaults are medium. | `string` | `"medium"` | no |
| <a name="input_storage_class"></a> [storage\_class](#input\_storage\_class) | StorageClass for the PVC-backed monitoring workloads (Alertmanager, the Loki ruler, and Thanos<br/>receive/compactor/store-gateway). Null uses the cluster default.<br/><br/>Must be a Hyperdisk class on C4/C4A/N4, which take only Hyperdisk — every default GKE class is<br/>Persistent Disk and fails to attach there. The examples create one and pass it here. | `string` | `null` | no |
| <a name="input_tolerations"></a> [tolerations](#input\_tolerations) | Tolerations for the monitoring workloads, including the Alloy agent DaemonSet. | <pre>list(object({<br/>    key      = optional(string)<br/>    operator = optional(string, "Equal")<br/>    value    = optional(string)<br/>    effect   = optional(string)<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_grafana_admin_password"></a> [grafana\_admin\_password](#output\_grafana\_admin\_password) | Grafana admin password. |
| <a name="output_grafana_database_endpoint"></a> [grafana\_database\_endpoint](#output\_grafana\_database\_endpoint) | `host:port` of the database backing Grafana's state, or null when Grafana is on SQLite. |
| <a name="output_grafana_database_password"></a> [grafana\_database\_password](#output\_grafana\_database\_password) | Password for the Grafana database user. Generated when this module creates the instance. |
| <a name="output_grafana_url"></a> [grafana\_url](#output\_grafana\_url) | URL for Grafana: the external one when `grafana_load_balancer` sets a host, the in-cluster Service otherwise — in which case reaching it means a port-forward. With a load balancer but no host, read the address from the Service; nothing here publishes DNS. |
| <a name="output_logs_bucket"></a> [logs\_bucket](#output\_logs\_bucket) | GCS bucket holding Loki chunks and the ruler's state. |
| <a name="output_logs_url"></a> [logs\_url](#output\_logs\_url) | Loki read endpoint. |
| <a name="output_metrics_bucket"></a> [metrics\_bucket](#output\_metrics\_bucket) | GCS bucket holding Thanos blocks. |
| <a name="output_metrics_url"></a> [metrics\_url](#output\_metrics\_url) | Thanos Query endpoint. Prometheus-API-compatible. |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace the monitoring stack is installed into. |
| <a name="output_service_account_emails"></a> [service\_account\_emails](#output\_service\_account\_emails) | Google service account emails, by backend. |
| <a name="output_workload_identity_subjects"></a> [workload\_identity\_subjects](#output\_workload\_identity\_subjects) | Kubernetes service-account subjects the Workload Identity bindings are scoped to. Emitted by the monitoring module from the names the chart actually renders, so a mismatch with the bindings above is visible rather than silent. |
