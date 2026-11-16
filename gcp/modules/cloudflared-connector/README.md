# cloudflared connector (GCP)

Runs Cloudflare Tunnel connectors (`cloudflared`) as a regional managed
instance group inside a VPC, so a tunnel created with
`cloudflare/modules/tunnel` can reach a Materialize environment's internal
load balancers.

The VMs have no public IP and no inbound firewall rules: `cloudflared` only
dials out to Cloudflare, so the subnetwork needs outbound internet access
(for example Cloud NAT). The tunnel token is stored in Secret Manager and
read at boot by the VMs' service account, whose only grant is read access
to that secret.

Requires the Secret Manager API (`secretmanager.googleapis.com`) in the
project.

## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 8.0, < 9 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_google"></a> [google](#provider\_google) | >= 8.0, < 9 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [google_compute_instance_template.connector](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_instance_template) | resource |
| [google_compute_region_instance_group_manager.connector](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_region_instance_group_manager) | resource |
| [google_project_iam_member.connector_secret_access](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_secret_manager_secret.tunnel_token](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret) | resource |
| [google_secret_manager_secret_version.tunnel_token](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret_version) | resource |
| [google_service_account.connector](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_project.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/project) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cloudflared_image"></a> [cloudflared\_image](#input\_cloudflared\_image) | cloudflared container image. | `string` | `"cloudflare/cloudflared:2026.11.0"` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels applied to connector resources. | `map(string)` | `{}` | no |
| <a name="input_machine_type"></a> [machine\_type](#input\_machine\_type) | Machine type for connector VMs. | `string` | `"e2-small"` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix for resource names. | `string` | n/a | yes |
| <a name="input_network"></a> [network](#input\_network) | Name or self link of the VPC network the connectors join. It needs outbound internet access (for example Cloud NAT). | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | GCP project to run the connectors in. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | Region for the connector instance group. | `string` | n/a | yes |
| <a name="input_replicas"></a> [replicas](#input\_replicas) | Number of connector VMs. Cloudflare balances across them; 2 or more survives a VM or zone loss. | `number` | `2` | no |
| <a name="input_subnetwork"></a> [subnetwork](#input\_subnetwork) | Name or self link of the subnetwork the connectors join. It must be able to reach the Materialize load balancers. | `string` | n/a | yes |
| <a name="input_tunnel_token"></a> [tunnel\_token](#input\_tunnel\_token) | Cloudflare tunnel token the connectors run with. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instance_group"></a> [instance\_group](#output\_instance\_group) | Self link of the connector instance group. |
| <a name="output_service_account_email"></a> [service\_account\_email](#output\_service\_account\_email) | Service account the connectors run as. |
| <a name="output_tunnel_token_secret"></a> [tunnel\_token\_secret](#output\_tunnel\_token\_secret) | Secret Manager secret holding the tunnel token. |
