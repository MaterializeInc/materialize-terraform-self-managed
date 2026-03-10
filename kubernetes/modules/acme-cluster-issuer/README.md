## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_kubectl"></a> [kubectl](#requirement\_kubectl) | ~> 2.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_kubectl"></a> [kubectl](#provider\_kubectl) | ~> 2.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [kubectl_manifest.acme_cluster_issuer](https://registry.terraform.io/providers/alekc/kubectl/latest/docs/resources/manifest) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_acme_email"></a> [acme\_email](#input\_acme\_email) | Email address for ACME registration. | `string` | n/a | yes |
| <a name="input_acme_server"></a> [acme\_server](#input\_acme\_server) | ACME server URL. | `string` | `"https://acme-v02.api.letsencrypt.org/directory"` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix for the ClusterIssuer name. | `string` | n/a | yes |
| <a name="input_solver_config"></a> [solver\_config](#input\_solver\_config) | Cloud-specific DNS01 solver configuration to inject into the ClusterIssuer spec. | `any` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_issuer_name"></a> [issuer\_name](#output\_issuer\_name) | The name of the ACME ClusterIssuer. |
