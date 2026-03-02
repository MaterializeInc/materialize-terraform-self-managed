## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | >= 2.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [kubernetes_network_policy_v1.allow_all_egress_instance](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/network_policy_v1) | resource |
| [kubernetes_network_policy_v1.allow_all_egress_operator](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/network_policy_v1) | resource |
| [kubernetes_network_policy_v1.allow_from_operator](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/network_policy_v1) | resource |
| [kubernetes_network_policy_v1.default_deny_instance](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/network_policy_v1) | resource |
| [kubernetes_network_policy_v1.default_deny_operator](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/network_policy_v1) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_enable_default_deny"></a> [enable\_default\_deny](#input\_enable\_default\_deny) | Enable default deny policies for operator and instance namespaces | `bool` | `true` | no |
| <a name="input_instance_namespaces"></a> [instance\_namespaces](#input\_instance\_namespaces) | List of namespaces where Materialize instances are deployed | `list(string)` | `[]` | no |
| <a name="input_operator_namespace"></a> [operator\_namespace](#input\_operator\_namespace) | The namespace where the Materialize operator is installed | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_instance_policies"></a> [instance\_policies](#output\_instance\_policies) | Network policies created in instance namespaces |
| <a name="output_operator_policies"></a> [operator\_policies](#output\_operator\_policies) | Network policies created in the operator namespace |
