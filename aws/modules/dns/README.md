Adds records for a set of hostnames to an existing Route 53 hosted zone and, optionally,
gives cert-manager an identity that can answer ACME DNS-01 challenges in it. The
module looks the hosted zone up and never creates, changes or deletes it.
A record that already exists in the hosted zone must be imported or removed
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
  source = "github.com/MaterializeInc/materialize-terraform-self-managed//aws/modules/dns?ref=<tag>"

  name_prefix = var.name_prefix
  zone_id     = "Z0123456789ABCDEFGHIJ"
  stem_domain = "mz.example.com"

  # The NLB has a hostname rather than an IP, so its names are CNAMEs. A
  # CNAME cannot sit at the zone's apex, which "@" is not here.
  subdomains = {
    console   = { subdomain = "@", type = "CNAME" }
    balancerd = { type = "CNAME" }
    grafana   = { create = false }
  }
  records = {
    console   = [module.materialize_nlb.nlb_dns_name]
    balancerd = [module.materialize_nlb.nlb_dns_name]
  }

  cert_manager_dns01 = {
    oidc_provider_arn       = module.eks.oidc_provider_arn
    cluster_oidc_issuer_url = module.eks.cluster_oidc_issuer_url
  }
}
```

Here `module.dns.fqdns.console` is `mz.example.com`, and
`module.dns.fqdns.grafana` is `grafana.mz.example.com` with no record created.

## DNS-01 for cert-manager

With `cert_manager_dns01` set, the module creates an IAM role that cert-manager's Kubernetes service account assumes through IRSA, allowed only to change TXT records named `_acme-challenge` under `stem_domain` in the hosted zone. Its outputs
plug into the `cert-manager` and `letsencrypt-cluster-issuer` modules, so the
issuer can prove control of any name under `stem_domain` without the balancer
or console being reachable from the internet. With IRSA, `cert_manager_pod_labels` is always empty; it is there so the wiring reads the same on every cloud.

```hcl
module "cert_manager" {
  source = "github.com/MaterializeInc/materialize-terraform-self-managed//kubernetes/modules/cert-manager?ref=<tag>"

  service_account_annotations = module.dns.cert_manager_service_account_annotations
  pod_labels                  = module.dns.cert_manager_pod_labels
}

module "letsencrypt_cluster_issuer" {
  source = "github.com/MaterializeInc/materialize-terraform-self-managed//kubernetes/modules/cert-manager/letsencrypt-cluster-issuer?ref=<tag>"

  name_prefix = var.name_prefix
  acme_email  = "platform-team@example.com"
  solvers     = [module.dns.acme_dns01_solver]

  depends_on = [module.cert_manager]
}
```

## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_role.cert_manager](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.cert_manager](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_route53_record.subdomains](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_route53_zone.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/route53_zone) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cert_manager_dns01"></a> [cert\_manager\_dns01](#input\_cert\_manager\_dns01) | Set to create the IAM role cert-manager's ACME DNS-01 solver assumes through IRSA, allowed only to change TXT records named \_acme-challenge under stem\_domain in this hosted zone, and to fill the cert\_manager\_service\_account\_annotations and acme\_dns01\_solver outputs. oidc\_provider\_arn and cluster\_oidc\_issuer\_url come from the eks module; namespace and service\_account\_name are where cert-manager's controller runs. Null, the default, creates no role. | <pre>object({<br/>    oidc_provider_arn       = string<br/>    cluster_oidc_issuer_url = string<br/>    namespace               = optional(string, "cert-manager")<br/>    service_account_name    = optional(string, "cert-manager")<br/>  })</pre> | `null` | no |
| <a name="input_iam_permissions_boundary"></a> [iam\_permissions\_boundary](#input\_iam\_permissions\_boundary) | ARN of the IAM permissions boundary to attach to all IAM roles created by this module. Required for BYOC deployments. | `string` | `null` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix to be used for resource names | `string` | n/a | yes |
| <a name="input_records"></a> [records](#input\_records) | Values of the record for each subdomains entry with create = true, keyed like subdomains: addresses for A and AAAA, one target name for a CNAME. They are kept out of subdomains so that the fqdns output never depends on them, which lets a load balancer configured with one of those names hand its address back here without a dependency cycle. | `map(list(string))` | `{}` | no |
| <a name="input_stem_domain"></a> [stem\_domain](#input\_stem\_domain) | Domain the subdomains are created under, such as mz.example.com in the zone example.com. It must be the zone's domain or a name inside it. Defaults to the zone's domain. | `string` | `null` | no |
| <a name="input_subdomains"></a> [subdomains](#input\_subdomains) | Hostnames under stem\_domain, keyed by the name the fqdns output uses for each. subdomain defaults to the key, and "@" means stem\_domain itself. When create is true, the default, the module creates a record of the given type (A, AAAA or CNAME; A by default) whose values come from records under the same key. With create false it only computes the name, for a record managed elsewhere. | <pre>map(object({<br/>    subdomain = optional(string)<br/>    create    = optional(bool, true)<br/>    type      = optional(string, "A")<br/>    ttl       = optional(number, 300)<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to resources created. | `map(string)` | `{}` | no |
| <a name="input_zone_id"></a> [zone\_id](#input\_zone\_id) | ID of the existing Route 53 hosted zone. The module adds records to the zone and never creates, changes or deletes the zone itself. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_acme_dns01_solver"></a> [acme\_dns01\_solver](#output\_acme\_dns01\_solver) | cert-manager ACME solver that answers DNS-01 challenges for stem\_domain and its subdomains in this hosted zone, for an element of the letsencrypt-cluster-issuer module's solvers. Null when cert\_manager\_dns01 is null. |
| <a name="output_cert_manager_pod_labels"></a> [cert\_manager\_pod\_labels](#output\_cert\_manager\_pod\_labels) | Labels for cert-manager's controller pods, for the cert-manager module's pod\_labels. IRSA needs none, so this is always empty; it matches the GCP and Azure dns modules. |
| <a name="output_cert_manager_service_account_annotations"></a> [cert\_manager\_service\_account\_annotations](#output\_cert\_manager\_service\_account\_annotations) | Annotations for cert-manager's Kubernetes service account that give it the DNS-01 identity, for the cert-manager module's service\_account\_annotations. Empty when cert\_manager\_dns01 is null. |
| <a name="output_fqdns"></a> [fqdns](#output\_fqdns) | Fully qualified name of each entry in subdomains, keyed like subdomains, whether or not the module created its record. |
| <a name="output_stem_domain"></a> [stem\_domain](#output\_stem\_domain) | Domain the subdomains are created under. |
| <a name="output_zone_domain"></a> [zone\_domain](#output\_zone\_domain) | DNS name of the hosted zone, without the trailing dot. |
