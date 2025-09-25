## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 3.75.0 |
| <a name="requirement_external"></a> [external](#requirement\_external) | >= 2.3.4 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.5.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 3.75.0 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.5.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_federated_identity_credential.materialize_storage](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/federated_identity_credential) | resource |
| [azurerm_role_assignment.storage_blob_contributor](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_storage_account.materialize](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account) | resource |
| [azurerm_storage_container.materialize](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_container) | resource |
| [random_string.unique](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_container_access_type"></a> [container\_access\_type](#input\_container\_access\_type) | The Access Level configured for this Container. Valid values are: private, blob, container. | `string` | `"private"` | no |
| <a name="input_container_name"></a> [container\_name](#input\_container\_name) | The name of the Container which should be created within the Storage Account | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | The location where resources will be created | `string` | n/a | yes |
| <a name="input_oidc_issuer_url"></a> [oidc\_issuer\_url](#input\_oidc\_issuer\_url) | The OIDC issuer URL of the AKS cluster | `string` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefix to be used for resource names | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | The name of the resource group | `string` | n/a | yes |
| <a name="input_service_account_name"></a> [service\_account\_name](#input\_service\_account\_name) | Kubernetes service account name that will use workload identity | `string` | n/a | yes |
| <a name="input_service_account_namespace"></a> [service\_account\_namespace](#input\_service\_account\_namespace) | Kubernetes namespace for the service account that will use workload identity | `string` | n/a | yes |
| <a name="input_storage_account_tags"></a> [storage\_account\_tags](#input\_storage\_account\_tags) | Tags to apply to storage account | `map(string)` | `{}` | no |
| <a name="input_subnets"></a> [subnets](#input\_subnets) | The subnet of the vnet that should be able to access this storage account | `list(string)` | `[]` | no |
| <a name="input_workload_identity_id"></a> [workload\_identity\_id](#input\_workload\_identity\_id) | The ID of the workload identity for federated credential | `string` | n/a | yes |
| <a name="input_workload_identity_principal_id"></a> [workload\_identity\_principal\_id](#input\_workload\_identity\_principal\_id) | The principal ID of the workload identity | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_container_name"></a> [container\_name](#output\_container\_name) | The name of the storage container |
| <a name="output_federated_identity_credential_id"></a> [federated\_identity\_credential\_id](#output\_federated\_identity\_credential\_id) | The ID of the federated identity credential for workload identity |
| <a name="output_primary_blob_endpoint"></a> [primary\_blob\_endpoint](#output\_primary\_blob\_endpoint) | The primary blob endpoint |
| <a name="output_storage_account_name"></a> [storage\_account\_name](#output\_storage\_account\_name) | The name of the storage account |
