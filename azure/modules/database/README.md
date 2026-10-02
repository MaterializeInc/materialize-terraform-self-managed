## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 5.4.0, < 6.0.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.0, < 3.10.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 5.4.0, < 6.0.0 |
| <a name="provider_random"></a> [random](#provider\_random) | ~> 3.0, < 3.10.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_postgresql_flexible_server.postgres](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/postgresql_flexible_server) | resource |
| [azurerm_postgresql_flexible_server_database.databases](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/postgresql_flexible_server_database) | resource |
| [random_password.admin_password](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_administrator_login"></a> [administrator\_login](#input\_administrator\_login) | The administrator login name for the PostgreSQL server | `string` | n/a | yes |
| <a name="input_administrator_password"></a> [administrator\_password](#input\_administrator\_password) | The administrator password for the PostgreSQL server. If not provided, a random password will be generated. | `string` | `null` | no |
| <a name="input_backup_retention_days"></a> [backup\_retention\_days](#input\_backup\_retention\_days) | The number of days to retain backups | `number` | `7` | no |
| <a name="input_databases"></a> [databases](#input\_databases) | List of databases to create | <pre>list(object({<br/>    name      = string<br/>    charset   = optional(string, "UTF8")<br/>    collation = optional(string, "en_US.utf8")<br/>  }))</pre> | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | The location where resources will be created | `string` | n/a | yes |
| <a name="input_postgres_version"></a> [postgres\_version](#input\_postgres\_version) | The PostgreSQL version | `string` | n/a | yes |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefix to be used for resource names | `string` | n/a | yes |
| <a name="input_private_dns_zone_id"></a> [private\_dns\_zone\_id](#input\_private\_dns\_zone\_id) | The ID of the private DNS zone | `string` | n/a | yes |
| <a name="input_public_network_access_enabled"></a> [public\_network\_access\_enabled](#input\_public\_network\_access\_enabled) | Whether public network access is enabled | `bool` | `false` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | The name of the resource group | `string` | n/a | yes |
| <a name="input_server_name"></a> [server\_name](#input\_server\_name) | Name of the Flexible Server. Defaults to `<prefix>-pg`. Set it to adopt a server created outside Terraform, such as the Premium SSD v2 server scripts/azure-migrate-metadata-premium-ssd-v2.sh creates; changing it on an existing server replaces the server. | `string` | `null` | no |
| <a name="input_sku_name"></a> [sku\_name](#input\_sku\_name) | The SKU name for the PostgreSQL server, sku denotes the size of postgres server | `string` | n/a | yes |
| <a name="input_storage_iops"></a> [storage\_iops](#input\_storage\_iops) | Provisioned IOPS, 3000 to 80000. Required for, and only used with, `storage_type = "PremiumV2_LRS"`. Free up to 3000 below 400 GiB of storage, and up to 12000 from 400 GiB. | `number` | `null` | no |
| <a name="input_storage_mb"></a> [storage\_mb](#input\_storage\_mb) | The storage capacity in MB | `number` | `32768` | no |
| <a name="input_storage_throughput"></a> [storage\_throughput](#input\_storage\_throughput) | Provisioned throughput in MB/s, 125 to 1200. Required for, and only used with, `storage_type = "PremiumV2_LRS"`. Free up to 125 MB/s below 400 GiB of storage, and up to 500 MB/s from 400 GiB. | `number` | `null` | no |
| <a name="input_storage_type"></a> [storage\_type](#input\_storage\_type) | The disk type: `Premium_LRS` (Premium SSD) or `PremiumV2_LRS` (Premium SSD v2).<br/><br/>Premium SSD v2 is usually cheaper for the same performance and lets IOPS and throughput be set<br/>independently of size, but it needs a General Purpose or Memory Optimized `sku_name` and does<br/>not support storage autogrow or PostgreSQL 13 or older.<br/><br/>Changing this on an existing server replaces it, which destroys the Materialize metadata:<br/>Azure has no online migration between the two. To move an existing server, use<br/>scripts/azure-migrate-metadata-premium-ssd-v2.sh (see scripts/azure-migrate-metadata-premium-ssd-v2.md). | `string` | `"Premium_LRS"` | no |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | The ID of the subnet for PostgreSQL | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_administrator_login"></a> [administrator\_login](#output\_administrator\_login) | The administrator login name |
| <a name="output_administrator_password"></a> [administrator\_password](#output\_administrator\_password) | The administrator password (generated if not provided) |
| <a name="output_database_names"></a> [database\_names](#output\_database\_names) | List of database names |
| <a name="output_databases"></a> [databases](#output\_databases) | Map of created databases |
| <a name="output_server_fqdn"></a> [server\_fqdn](#output\_server\_fqdn) | The FQDN of the PostgreSQL server |
| <a name="output_server_id"></a> [server\_id](#output\_server\_id) | The ID of the PostgreSQL server |
| <a name="output_server_name"></a> [server\_name](#output\_server\_name) | The name of the PostgreSQL server |
