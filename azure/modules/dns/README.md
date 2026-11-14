Adds records for a set of hostnames to an existing Azure DNS zone and, optionally,
gives cert-manager an identity that can answer ACME DNS-01 challenges in it. The
module looks the zone up and never creates, changes or deletes it.
A record that already exists in the zone must be imported or removed
before the module can create it.

## Hostnames

`stem_domain` is the domain the hostnames sit under, such as `mz.example.com` in
the zone `example.com`, and defaults to the zone's own domain. Each entry in
`subdomains` becomes `<subdomain>.<stem_domain>`, or `stem_domain` itself for
`"@"`; `subdomain` defaults to the entry's key. The `fqdns` output returns the
names under the same keys, so the rest of a configuration can take every
hostname from one place instead of a variable per hostname. An entry with
`create = false` only computes its name, for a record something else manages.

The values of each record come from `records`, keyed like `subdomains`, rather
than from the entry itself. `fqdns` depends only on `subdomains`, so a load
balancer configured with one of the names can hand its address back through
`records` without a dependency cycle.

```hcl
module "dns" {
  source = "github.com/MaterializeInc/materialize-terraform-self-managed//azure/modules/dns?ref=<tag>"

  prefix                   = var.prefix
  zone_name                = "example.com"
  zone_resource_group_name = "dns-zones"
  stem_domain              = "mz.example.com"

  subdomains = {
    console   = { subdomain = "@" }
    balancerd = {}
    grafana   = { create = false }
  }
  records = {
    console   = [module.load_balancers.console_load_balancer_ip]
    balancerd = [module.load_balancers.balancerd_load_balancer_ip]
  }

  cert_manager_dns01 = {
    oidc_issuer_url     = module.aks.cluster_oidc_issuer_url
    resource_group_name = azurerm_resource_group.materialize.name
    location            = var.location
  }
}
```

Here `module.dns.fqdns.console` is `mz.example.com`, and
`module.dns.fqdns.grafana` is `grafana.mz.example.com` with no record created.

## DNS-01 for cert-manager

With `cert_manager_dns01` set, the module creates a user-assigned managed identity with DNS Zone Contributor on the zone only, and a federated credential that lets cert-manager's Kubernetes service account act as it through Azure Workload Identity. Its outputs
plug into the `cert-manager` and `letsencrypt-cluster-issuer` modules, so the
issuer can prove control of any name under `stem_domain` without the balancer
or console being reachable from the internet. Azure Workload Identity selects pods by label, so `cert_manager_pod_labels` carries the `azure.workload.identity/use` label and `cert_manager_service_account_annotations` is always empty.

```hcl
module "cert_manager" {
  source = "github.com/MaterializeInc/materialize-terraform-self-managed//kubernetes/modules/cert-manager?ref=<tag>"

  service_account_annotations = module.dns.cert_manager_service_account_annotations
  pod_labels                  = module.dns.cert_manager_pod_labels
}

module "letsencrypt_cluster_issuer" {
  source = "github.com/MaterializeInc/materialize-terraform-self-managed//kubernetes/modules/cert-manager/letsencrypt-cluster-issuer?ref=<tag>"

  name_prefix = var.prefix
  acme_email  = "platform-team@example.com"
  solvers     = [module.dns.acme_dns01_solver]

  depends_on = [module.cert_manager]
}
```

## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 5.4.0, < 6.0.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 5.4.0, < 6.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_dns_a_record.subdomains](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/dns_a_record) | resource |
| [azurerm_dns_aaaa_record.subdomains](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/dns_aaaa_record) | resource |
| [azurerm_dns_cname_record.subdomains](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/dns_cname_record) | resource |
| [azurerm_federated_identity_credential.cert_manager](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/federated_identity_credential) | resource |
| [azurerm_role_assignment.cert_manager](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_user_assigned_identity.cert_manager](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [azurerm_dns_zone.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/dns_zone) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cert_manager_dns01"></a> [cert\_manager\_dns01](#input\_cert\_manager\_dns01) | Set to create the user-assigned managed identity cert-manager's ACME DNS-01 solver acts as through Azure Workload Identity, with DNS Zone Contributor on this zone only, and to fill the cert\_manager\_pod\_labels and acme\_dns01\_solver outputs. oidc\_issuer\_url comes from the aks module, and the identity is created in resource\_group\_name and location. namespace and service\_account\_name are where cert-manager's controller runs, and environment is the Azure cloud cert-manager talks to. Null, the default, creates no identity. | <pre>object({<br/>    oidc_issuer_url      = string<br/>    resource_group_name  = string<br/>    location             = string<br/>    namespace            = optional(string, "cert-manager")<br/>    service_account_name = optional(string, "cert-manager")<br/>    environment          = optional(string, "AzurePublicCloud")<br/>  })</pre> | `null` | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefix to be used for resource names | `string` | n/a | yes |
| <a name="input_records"></a> [records](#input\_records) | Values of the record for each subdomains entry with create = true, keyed like subdomains: addresses for A and AAAA, one target name for a CNAME. They are kept out of subdomains so that the fqdns output never depends on them, which lets a load balancer configured with one of those names hand its address back here without a dependency cycle. | `map(list(string))` | `{}` | no |
| <a name="input_stem_domain"></a> [stem\_domain](#input\_stem\_domain) | Domain the subdomains are created under, such as mz.example.com in the zone example.com. It must be the zone's domain or a name inside it. Defaults to the zone's domain. | `string` | `null` | no |
| <a name="input_subdomains"></a> [subdomains](#input\_subdomains) | Hostnames under stem\_domain, keyed by the name the fqdns output uses for each. subdomain defaults to the key, and "@" means stem\_domain itself. When create is true, the default, the module creates a record of the given type (A, AAAA or CNAME; A by default) whose values come from records under the same key. With create false it only computes the name, for a record managed elsewhere. | <pre>map(object({<br/>    subdomain = optional(string)<br/>    create    = optional(bool, true)<br/>    type      = optional(string, "A")<br/>    ttl       = optional(number, 300)<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to resources created. | `map(string)` | `{}` | no |
| <a name="input_zone_name"></a> [zone\_name](#input\_zone\_name) | Name of the existing Azure DNS zone, such as example.com. The module adds records to the zone and never creates, changes or deletes the zone itself. | `string` | n/a | yes |
| <a name="input_zone_resource_group_name"></a> [zone\_resource\_group\_name](#input\_zone\_resource\_group\_name) | Resource group that holds the DNS zone, in the subscription the azurerm provider is configured for. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_acme_dns01_solver"></a> [acme\_dns01\_solver](#output\_acme\_dns01\_solver) | cert-manager ACME solver that answers DNS-01 challenges for stem\_domain and its subdomains in this zone, for an element of the letsencrypt-cluster-issuer module's solvers. Null when cert\_manager\_dns01 is null. |
| <a name="output_cert_manager_pod_labels"></a> [cert\_manager\_pod\_labels](#output\_cert\_manager\_pod\_labels) | Labels for cert-manager's controller pods that opt them into Azure Workload Identity, for the cert-manager module's pod\_labels. Empty when cert\_manager\_dns01 is null. |
| <a name="output_cert_manager_service_account_annotations"></a> [cert\_manager\_service\_account\_annotations](#output\_cert\_manager\_service\_account\_annotations) | Annotations for cert-manager's Kubernetes service account, for the cert-manager module's service\_account\_annotations. The solver names the managed identity by client ID, so this is always empty; it matches the AWS and GCP dns modules. |
| <a name="output_fqdns"></a> [fqdns](#output\_fqdns) | Fully qualified name of each entry in subdomains, keyed like subdomains, whether or not the module created its record. |
| <a name="output_stem_domain"></a> [stem\_domain](#output\_stem\_domain) | Domain the subdomains are created under. |
| <a name="output_zone_domain"></a> [zone\_domain](#output\_zone\_domain) | DNS name of the zone. |
