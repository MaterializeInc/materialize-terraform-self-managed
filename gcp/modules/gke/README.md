## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 7.22, < 8 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_google"></a> [google](#provider\_google) | >= 7.22, < 8 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [google_compute_firewall.conversion_webhook](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_firewall) | resource |
| [google_container_cluster.primary](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/container_cluster) | resource |
| [google_project_iam_member.orchestratord_cluster_viewer](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_pubsub_subscription.orchestratord_upgrade_notifications](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_subscription) | resource |
| [google_pubsub_subscription_iam_member.orchestratord_upgrade_notifications_subscriber](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_subscription_iam_member) | resource |
| [google_pubsub_topic.upgrade_notifications](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_topic) | resource |
| [google_service_account.gke_sa](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_service_account.workload_identity_sa](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_service_account_iam_binding.workload_identity](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_binding) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_secondary_range_name"></a> [cluster\_secondary\_range\_name](#input\_cluster\_secondary\_range\_name) | The name of the secondary range to use for pods | `string` | `"pods"` | no |
| <a name="input_datapath_provider"></a> [datapath\_provider](#input\_datapath\_provider) | The datapath provider (CNI) for the GKE cluster. ADVANCED\_DATAPATH is GKE Dataplane V2 (eBPF-based, enforces Kubernetes NetworkPolicy natively). DATAPATH\_PROVIDER\_UNSPECIFIED and LEGACY\_DATAPATH use the legacy GKE CNI, which silently ignores NetworkPolicy resources. GKE cannot change the datapath provider on an existing cluster: changing this forces the cluster to be rebuilt. | `string` | `"ADVANCED_DATAPATH"` | no |
| <a name="input_enable_node_local_dns"></a> [enable\_node\_local\_dns](#input\_enable\_node\_local\_dns) | Whether to enable GKE's NodeLocal DNSCache addon, which runs a DNS cache on every node. This is the supported way to get node-local DNS on GKE: with Dataplane V2 a self-deployed node-local-dns cannot intercept kube-dns traffic (service IPs are rewritten in eBPF before iptables sees them). Note: NodeLocal DNSCache caches cluster records for up to 5s even when CoreDNS serves TTL-0 records, and toggling this on an existing cluster recreates all node pools. | `bool` | `false` | no |
| <a name="input_enable_upgrade_notifications"></a> [enable\_upgrade\_notifications](#input\_enable\_upgrade\_notifications) | Publish GKE upgrade notifications to a Pub/Sub topic and let orchestratord's service account subscribe to them and read node pool state. Required for the operator module's enable\_node\_upgrade\_rollout\_trigger. | `bool` | `true` | no |
| <a name="input_gce_persistent_disk_csi_driver_enabled"></a> [gce\_persistent\_disk\_csi\_driver\_enabled](#input\_gce\_persistent\_disk\_csi\_driver\_enabled) | Whether to enable the GCE persistent disk CSI driver | `bool` | `true` | no |
| <a name="input_horizontal_pod_autoscaling_disabled"></a> [horizontal\_pod\_autoscaling\_disabled](#input\_horizontal\_pod\_autoscaling\_disabled) | Whether to disable horizontal pod autoscaling | `bool` | `false` | no |
| <a name="input_http_load_balancing_disabled"></a> [http\_load\_balancing\_disabled](#input\_http\_load\_balancing\_disabled) | Whether to disable HTTP load balancing | `bool` | `false` | no |
| <a name="input_k8s_apiserver_authorized_networks"></a> [k8s\_apiserver\_authorized\_networks](#input\_k8s\_apiserver\_authorized\_networks) | List of CIDR blocks to allow access to the Kubernetes master endpoint. Each entry should have cidr\_block and display\_name. Defaults to 0.0.0.0/0 to allow access from anywhere. | <pre>list(object({<br/>    cidr_block   = string<br/>    display_name = string<br/>  }))</pre> | <pre>[<br/>  {<br/>    "cidr_block": "0.0.0.0/0",<br/>    "display_name": "Authorized networks"<br/>  }<br/>]</pre> | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_master_ipv4_cidr_block"></a> [master\_ipv4\_cidr\_block](#input\_master\_ipv4\_cidr\_block) | The IP range in CIDR notation to use for the hosted master network. This range must not overlap with any other ranges in use within the cluster's network. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | The namespace where the Materialize Operator will be installed | `string` | n/a | yes |
| <a name="input_network_name"></a> [network\_name](#input\_network\_name) | The name of the VPC network | `string` | n/a | yes |
| <a name="input_networking_mode"></a> [networking\_mode](#input\_networking\_mode) | The networking mode for the GKE cluster | `string` | `"VPC_NATIVE"` | no |
| <a name="input_node_locations"></a> [node\_locations](#input\_node\_locations) | List of zones where cluster nodes will be created. Must be zones within the cluster's region. When null (the default), GKE distributes nodes across available zones. | `list(string)` | `null` | no |
| <a name="input_orchestratord_service_account_name"></a> [orchestratord\_service\_account\_name](#input\_orchestratord\_service\_account\_name) | The name of the operator's Kubernetes service account bound to the workload identity service account. Must match the Materialize operator chart's serviceAccount.name value (the operator module leaves this at the chart default, "orchestratord"). | `string` | `"orchestratord"` | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefix to be used for resource names | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The ID of the project where resources will be created | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | The region where resources will be created | `string` | n/a | yes |
| <a name="input_release_channel"></a> [release\_channel](#input\_release\_channel) | The release channel for the GKE cluster | `string` | `"REGULAR"` | no |
| <a name="input_services_secondary_range_name"></a> [services\_secondary\_range\_name](#input\_services\_secondary\_range\_name) | The name of the secondary range to use for services | `string` | `"services"` | no |
| <a name="input_subnet_name"></a> [subnet\_name](#input\_subnet\_name) | The name of the subnet | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cluster_ca_certificate"></a> [cluster\_ca\_certificate](#output\_cluster\_ca\_certificate) | n/a |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | The public endpoint of the GKE cluster |
| <a name="output_cluster_location"></a> [cluster\_location](#output\_cluster\_location) | The location of the GKE cluster |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | The name of the GKE cluster |
| <a name="output_cluster_private_endpoint"></a> [cluster\_private\_endpoint](#output\_cluster\_private\_endpoint) | The private endpoint of the GKE cluster (used by nodes and VPC resources) |
| <a name="output_node_locations"></a> [node\_locations](#output\_node\_locations) | The zones where cluster nodes are created |
| <a name="output_service_account_email"></a> [service\_account\_email](#output\_service\_account\_email) | The email of the GKE service account |
| <a name="output_upgrade_notification_subscription"></a> [upgrade\_notification\_subscription](#output\_upgrade\_notification\_subscription) | The Pub/Sub subscription (projects/{project}/subscriptions/{name}) on which orchestratord receives GKE upgrade notifications. Null unless enable\_upgrade\_notifications is set. |
| <a name="output_workload_identity_sa_email"></a> [workload\_identity\_sa\_email](#output\_workload\_identity\_sa\_email) | The email of the Workload Identity service account |
