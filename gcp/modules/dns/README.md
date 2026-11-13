Adds records for a set of hostnames to an existing Cloud DNS managed zone and, optionally,
gives cert-manager an identity that can answer ACME DNS-01 challenges in it. The
module looks the managed zone up and never creates, changes or deletes it.
A record that already exists in the managed zone must be imported or removed
before the module can create it.

## Hostnames

`stem_domain` is the domain the hostnames sit under, such as `mz.example.com` in
the zone `example.com`, and defaults to the zone's own domain. Each entry in
`subdomains` becomes `<subdomain>.<stem_domain>`, or `stem_domain` itself for
`"@"`; `subdomain` defaults to the entry's key. The `fqdns` output returns the
names under the same keys, so the rest of a configuration can take every
hostname from one place instead of a variable per hostname. An entry with
`create = false` only computes its name, for a record something else manages.

```hcl
module "dns" {
  source = "github.com/MaterializeInc/materialize-terraform-self-managed//gcp/modules/dns?ref=<tag>"

  project_id  = var.project_id
  prefix      = var.prefix
  zone_name   = "example-com"
  stem_domain = "mz.example.com"

  subdomains = {
    console   = { subdomain = "@", records = [module.load_balancers.console_load_balancer_ip] }
    balancerd = { records = [module.load_balancers.balancerd_load_balancer_ip] }
    grafana   = { create = false }
  }

  cert_manager_dns01 = {}
}
```

Here `module.dns.fqdns.console` is `mz.example.com`, and
`module.dns.fqdns.grafana` is `grafana.mz.example.com` with no record created.

## DNS-01 for cert-manager

With `cert_manager_dns01` set, the module creates a Google service account with `roles/dns.admin` on the managed zone only, and lets cert-manager's Kubernetes service account act as it through GKE Workload Identity. Its outputs
plug into the `cert-manager` and `letsencrypt-cluster-issuer` modules, so the
issuer can prove control of any name under `stem_domain` without the balancer
or console being reachable from the internet. On GKE, `cert_manager_pod_labels` is always empty; it is there so the wiring reads the same on every cloud.

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
| [google_dns_managed_zone_iam_member.cert_manager](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/dns_managed_zone_iam_member) | resource |
| [google_dns_record_set.subdomains](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/dns_record_set) | resource |
| [google_service_account.cert_manager](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_service_account_iam_member.cert_manager_workload_identity](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_member) | resource |
| [google_dns_managed_zone.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/dns_managed_zone) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cert_manager_dns01"></a> [cert\_manager\_dns01](#input\_cert\_manager\_dns01) | Set to create the Google service account cert-manager's ACME DNS-01 solver acts as through GKE Workload Identity, with roles/dns.admin on the managed zone only, and to fill the cert\_manager\_service\_account\_annotations and acme\_dns01\_solver outputs. namespace and service\_account\_name are where cert-manager's controller runs. Null, the default, creates no identity. | <pre>object({<br/>    namespace            = optional(string, "cert-manager")<br/>    service_account_name = optional(string, "cert-manager")<br/>  })</pre> | `null` | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Prefix to be used for resource names | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | GCP project the GKE cluster runs in. The cert-manager Google service account is created here, and its Workload Identity binding uses this project's pool. | `string` | n/a | yes |
| <a name="input_stem_domain"></a> [stem\_domain](#input\_stem\_domain) | Domain the subdomains are created under, such as mz.example.com in the zone example.com. It must be the zone's domain or a name inside it. Defaults to the zone's domain. | `string` | `null` | no |
| <a name="input_subdomains"></a> [subdomains](#input\_subdomains) | Hostnames under stem\_domain, keyed by the name the fqdns output uses for each. subdomain defaults to the key, and "@" means stem\_domain itself. When create is true, the default, the module creates a record of the given type (A, AAAA or CNAME; A by default) with records as its values. With create false it only computes the name, for a record managed elsewhere. | <pre>map(object({<br/>    subdomain = optional(string)<br/>    create    = optional(bool, true)<br/>    type      = optional(string, "A")<br/>    records   = optional(list(string), [])<br/>    ttl       = optional(number, 300)<br/>  }))</pre> | `{}` | no |
| <a name="input_zone_name"></a> [zone\_name](#input\_zone\_name) | Name of the existing Cloud DNS managed zone, as Cloud DNS lists it, not its DNS name. The module adds records to the zone and never creates, changes or deletes the zone itself. | `string` | n/a | yes |
| <a name="input_zone_project_id"></a> [zone\_project\_id](#input\_zone\_project\_id) | Project that holds the managed zone. Defaults to project\_id. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_acme_dns01_solver"></a> [acme\_dns01\_solver](#output\_acme\_dns01\_solver) | cert-manager ACME solver that answers DNS-01 challenges for stem\_domain and its subdomains in this managed zone, for an element of the letsencrypt-cluster-issuer module's solvers. Null when cert\_manager\_dns01 is null. |
| <a name="output_cert_manager_pod_labels"></a> [cert\_manager\_pod\_labels](#output\_cert\_manager\_pod\_labels) | Labels for cert-manager's controller pods, for the cert-manager module's pod\_labels. GKE Workload Identity needs none, so this is always empty; it matches the AWS and Azure dns modules. |
| <a name="output_cert_manager_service_account_annotations"></a> [cert\_manager\_service\_account\_annotations](#output\_cert\_manager\_service\_account\_annotations) | Annotations for cert-manager's Kubernetes service account that give it the DNS-01 identity, for the cert-manager module's service\_account\_annotations. Empty when cert\_manager\_dns01 is null. |
| <a name="output_fqdns"></a> [fqdns](#output\_fqdns) | Fully qualified name of each entry in subdomains, keyed like subdomains, whether or not the module created its record. |
| <a name="output_stem_domain"></a> [stem\_domain](#output\_stem\_domain) | Domain the subdomains are created under. |
| <a name="output_zone_domain"></a> [zone\_domain](#output\_zone\_domain) | DNS name of the managed zone, without the trailing dot. |
