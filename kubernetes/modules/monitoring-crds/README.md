## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 2.5.0, < 2.18.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.10.0, < 3.4.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_helm"></a> [helm](#provider\_helm) | >= 2.5.0, < 2.18.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | >= 2.10.0, < 3.4.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [helm_release.crds](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_namespace.monitoring](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_chart_registry"></a> [chart\_registry](#input\_chart\_registry) | OCI registry holding the materialize-monitoring charts. Override for a mirrored or air-gapped registry. Keep it in step with the monitoring module's. | `string` | `"oci://ghcr.io/materializeinc/helm-charts"` | no |
| <a name="input_chart_version"></a> [chart\_version](#input\_chart\_version) | Version of the materialize-monitoring-crds chart. It is versioned separately from the monitoring chart. | `string` | `"0.3.0"` | no |
| <a name="input_create_namespace"></a> [create\_namespace](#input\_create\_namespace) | Create the namespace. Set false when something else already creates it before this module runs. | `bool` | `true` | no |
| <a name="input_install_crds"></a> [install\_crds](#input\_install\_crds) | Install the materialize-monitoring-crds chart (prometheus-operator and grafana-operator CRDs).<br/><br/>Set false when the monitoring stack is not installed, or when the cluster already has these<br/>CRDs from elsewhere, such as kube-prometheus-stack or a platform team that owns CRDs centrally;<br/>Helm cannot install objects another release owns. Charts that ship ServiceMonitors then have to<br/>wait for whoever does install them.<br/><br/>The CRDs carry `helm.sh/resource-policy: keep`, so turning this off uninstalls the release but<br/>leaves the CRDs, and every resource that uses them, in place. | `bool` | `true` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace for the monitoring stack. Holds the CRDs release's metadata, and is where the monitoring module installs everything else. | `string` | `"monitoring"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_crds_installed"></a> [crds\_installed](#output\_crds\_installed) | Whether this module installed the monitoring CRDs.<br/><br/>Pass it to a module's ServiceMonitor toggle rather than a literal: it is read from the release,<br/>so anything that uses it waits for the CRDs to exist. |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | The monitoring namespace, once it exists. |
