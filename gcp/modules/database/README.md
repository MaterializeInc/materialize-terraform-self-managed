## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 6.31, < 7 |

## Providers

No providers.

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_postgresql"></a> [postgresql](#module\_postgresql) | terraform-google-modules/sql-db/google//modules/postgresql | 26.1.1 |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_backup_enabled"></a> [backup\_enabled](#input\_backup\_enabled) | Enable backup configuration | `bool` | `true` | no |
| <a name="input_backup_retained_backups"></a> [backup\_retained\_backups](#input\_backup\_retained\_backups) | Number of backups to retain | `number` | `7` | no |
| <a name="input_backup_retention_unit"></a> [backup\_retention\_unit](#input\_backup\_retention\_unit) | The unit of time for backup retention | `string` | `"COUNT"` | no |
| <a name="input_backup_start_time"></a> [backup\_start\_time](#input\_backup\_start\_time) | HH:MM format time indicating when backup starts | `string` | `"03:00"` | no |
| <a name="input_create_timeout"></a> [create\_timeout](#input\_create\_timeout) | Timeout for create operations | `string` | `"60m"` | no |
| <a name="input_database_deletion_policy"></a> [database\_deletion\_policy](#input\_database\_deletion\_policy) | Deletion policy for databases | `string` | `"ABANDON"` | no |
| <a name="input_database_flags"></a> [database\_flags](#input\_database\_flags) | List of database flags to apply to the instance | <pre>list(object({<br/>    name  = string<br/>    value = string<br/>  }))</pre> | `[]` | no |
| <a name="input_databases"></a> [databases](#input\_databases) | List of additional databases to create | <pre>list(object({<br/>    name      = string<br/>    charset   = optional(string, "UTF8")<br/>    collation = optional(string, "en_US.UTF8")<br/>  }))</pre> | n/a | yes |
| <a name="input_db_version"></a> [db\_version](#input\_db\_version) | The PostgreSQL version to use | `string` | `"POSTGRES_15"` | no |
| <a name="input_delete_timeout"></a> [delete\_timeout](#input\_delete\_timeout) | Timeout for delete operations | `string` | `"45m"` | no |
| <a name="input_disk_autoresize"></a> [disk\_autoresize](#input\_disk\_autoresize) | Enable automatic increase of disk size | `bool` | `true` | no |
| <a name="input_disk_autoresize_limit"></a> [disk\_autoresize\_limit](#input\_disk\_autoresize\_limit) | The maximum size to which storage can be auto increased | `number` | `0` | no |
| <a name="input_disk_size"></a> [disk\_size](#input\_disk\_size) | The disk size for the database instance in GB | `number` | `null` | no |
| <a name="input_disk_type"></a> [disk\_type](#input\_disk\_type) | The disk type for the database instance | `string` | `"PD_SSD"` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels to apply to Cloud SQL instances | `map(string)` | `{}` | no |
| <a name="input_maintenance_window_day"></a> [maintenance\_window\_day](#input\_maintenance\_window\_day) | Day of week for maintenance window (1-7) | `number` | `7` | no |
| <a name="input_maintenance_window_hour"></a> [maintenance\_window\_hour](#input\_maintenance\_window\_hour) | Hour of day for maintenance window (0-23) | `number` | `3` | no |
| <a name="input_maintenance_window_update_track"></a> [maintenance\_window\_update\_track](#input\_maintenance\_window\_update\_track) | Maintenance window update track | `string` | `"stable"` | no |
| <a name="input_network_id"></a> [network\_id](#input\_network\_id) | The ID of the VPC network to connect the database to | `string` | n/a | yes |
| <a name="input_point_in_time_recovery_enabled"></a> [point\_in\_time\_recovery\_enabled](#input\_point\_in\_time\_recovery\_enabled) | Enable point in time recovery | `bool` | `true` | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefix to be used for resource names | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The ID of the project where resources will be created | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | The region where resources will be created | `string` | n/a | yes |
| <a name="input_tier"></a> [tier](#input\_tier) | The machine tier for the database instance | `string` | n/a | yes |
| <a name="input_update_timeout"></a> [update\_timeout](#input\_update\_timeout) | Timeout for update operations | `string` | `"45m"` | no |
| <a name="input_user_deletion_policy"></a> [user\_deletion\_policy](#input\_user\_deletion\_policy) | Deletion policy for users | `string` | `"ABANDON"` | no |
| <a name="input_users"></a> [users](#input\_users) | List of users to create | <pre>list(object({<br/>    name     = string<br/>    password = optional(string, null)<br/>  }))</pre> | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_database_names"></a> [database\_names](#output\_database\_names) | List of database names |
| <a name="output_databases"></a> [databases](#output\_databases) | List of created databases |
| <a name="output_instance_name"></a> [instance\_name](#output\_instance\_name) | The name of the database instance |
| <a name="output_private_ip"></a> [private\_ip](#output\_private\_ip) | The private IP address of the database instance |
| <a name="output_user_names"></a> [user\_names](#output\_user\_names) | List of database user names |
| <a name="output_users"></a> [users](#output\_users) | List of created users with their credentials |
