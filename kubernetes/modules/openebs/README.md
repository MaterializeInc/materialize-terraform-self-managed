## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 2.5.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.10.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_helm"></a> [helm](#provider\_helm) | >= 2.5.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | >= 2.10.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [helm_release.openebs](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_namespace.openebs](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_create_openebs_namespace"></a> [create\_openebs\_namespace](#input\_create\_openebs\_namespace) | Whether to create the OpenEBS namespace. Set to false if the namespace already exists. | `bool` | `true` | no |
| <a name="input_enable_mayastor"></a> [enable\_mayastor](#input\_enable\_mayastor) | Whether to enable Mayastor in OpenEBS | `bool` | `false` | no |
| <a name="input_install_openebs"></a> [install\_openebs](#input\_install\_openebs) | Whether to install OpenEBS | `bool` | `true` | no |
| <a name="input_install_openebs_crds"></a> [install\_openebs\_crds](#input\_install\_openebs\_crds) | Whether to install OpenEBS CRDs | `bool` | `false` | no |
| <a name="input_openebs_namespace"></a> [openebs\_namespace](#input\_openebs\_namespace) | Namespace for OpenEBS components | `string` | `"openebs"` | no |
| <a name="input_openebs_version"></a> [openebs\_version](#input\_openebs\_version) | Version of OpenEBS Helm chart to install | `string` | `"4.2.0"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_helm_release_name"></a> [helm\_release\_name](#output\_helm\_release\_name) | The name of the OpenEBS Helm release |
| <a name="output_helm_release_status"></a> [helm\_release\_status](#output\_helm\_release\_status) | The status of the OpenEBS Helm release |
| <a name="output_helm_release_version"></a> [helm\_release\_version](#output\_helm\_release\_version) | The version of the installed OpenEBS Helm chart |
| <a name="output_openebs_installed"></a> [openebs\_installed](#output\_openebs\_installed) | Whether OpenEBS is installed |
| <a name="output_openebs_namespace"></a> [openebs\_namespace](#output\_openebs\_namespace) | The namespace where OpenEBS is installed |
