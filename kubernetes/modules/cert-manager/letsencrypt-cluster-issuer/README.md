Creates a cert-manager ACME `ClusterIssuer`. Until `acme_server_prod` is set
to true it is `<name_prefix>-letsencrypt-staging` and issues from Let's
Encrypt staging; after that it is `<name_prefix>-letsencrypt` and issues from
Let's Encrypt production. `acme_server` points `<name_prefix>-letsencrypt` at
any other ACME server instead. Each issuer keeps its ACME account key in the
Secret `<issuer name>-account-key` in cert-manager's namespace, and the
`issuer_name` output always names the current issuer.

The module does not choose a challenge type or a DNS provider. The `solvers`
input is passed through unchanged as the issuer's `spec.acme.solvers`, so any
solver cert-manager supports works here; see cert-manager's
[ACME documentation](https://cert-manager.io/docs/configuration/acme/) for
the fields. A DNS-01 solver is the usual choice for Materialize, because it
does not need the balancer or console to be reachable from the internet
before the first certificate is issued.

A DNS-01 solver needs credentials for the DNS provider. The examples below
give cert-manager's controller a cloud identity through its Kubernetes service
account, using the `service_account_annotations` and `pod_labels` inputs of
the [`cert-manager`](..) module, so no static keys are stored in
the cluster. Set `ref=` to the latest tagged version of this repository.

## Staging first, then production

Let's Encrypt production limits how many validations may fail for a hostname
each hour, so mistakes while a solver is being set up can hold up issuance.
Staging has far higher limits and signs from an untrusted test root, which
browsers warn about. The issuer starts on staging, and moving it to
production is a separate apply after a person has reviewed the result:

1. Apply with `acme_server_prod` unset, as in the examples below. Check that
   every Certificate using the issuer becomes ready, for example with
   `kubectl get certificates --all-namespaces`.
2. Set `acme_server_prod = true` and apply. Terraform replaces
   `<name_prefix>-letsencrypt-staging` with `<name_prefix>-letsencrypt`, and
   `issuer_name` changes with it. cert-manager reissues a Certificate as soon
   as its issuerRef names the new issuer, so certificates whose issuerRef
   comes from `issuer_name` move to production without a manual renewal. For
   a Materialize instance, that happens when the operator applies the new
   `issuer_ref`; on the `v1alpha1` CRD, that waits for a `request_rollout`.

The staging account key Secret stays in cert-manager's namespace after the
staging issuer is deleted, and can be deleted by hand.

## Example: Google Cloud DNS with GKE Workload Identity

The Google service account needs `roles/dns.admin` on the project that holds
the zone, and the cert-manager Kubernetes service account must be allowed to
impersonate it. `cnameStrategy = "Follow"` lets a name whose zone cert-manager
cannot write delegate its challenge: a CNAME at `_acme-challenge.<name>`
points into a zone it can write, and cert-manager writes the TXT record at the
CNAME's target.

```hcl
resource "google_service_account" "cert_manager" {
  project      = var.project_id
  account_id   = "cert-manager-dns01"
  display_name = "cert-manager Cloud DNS solver"
}

resource "google_project_iam_member" "cert_manager_dns" {
  project = var.project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.cert_manager.email}"
}

resource "google_service_account_iam_member" "cert_manager_workload_identity" {
  service_account_id = google_service_account.cert_manager.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[cert-manager/cert-manager]"
}

module "cert_manager" {
  source = "github.com/MaterializeInc/materialize-terraform-self-managed//kubernetes/modules/cert-manager?ref=<tag>"

  service_account_annotations = {
    "iam.gke.io/gcp-service-account" = google_service_account.cert_manager.email
  }
}

module "letsencrypt_cluster_issuer" {
  source = "github.com/MaterializeInc/materialize-terraform-self-managed//kubernetes/modules/cert-manager/letsencrypt-cluster-issuer?ref=<tag>"

  name_prefix = "my-mz"
  acme_email  = "platform-team@example.com"
  solvers = [
    {
      dns01 = {
        cnameStrategy = "Follow"
        cloudDNS = {
          project = var.project_id
        }
      }
    }
  ]

  depends_on = [module.cert_manager]
}
```

## Example: Amazon Route 53 with IRSA

The IAM role's trust policy must admit the service account
`system:serviceaccount:cert-manager:cert-manager` through the cluster's OIDC
provider, and its policy must allow `route53:GetChange` and, on the hosted
zone, `route53:ChangeResourceRecordSets` and
`route53:ListResourceRecordSets`. cert-manager's
[Route 53 documentation](https://cert-manager.io/docs/configuration/acme/dns01/route53/)
has the full policy. The `selector` limits the solver to names in the zone.

```hcl
module "cert_manager" {
  source = "github.com/MaterializeInc/materialize-terraform-self-managed//kubernetes/modules/cert-manager?ref=<tag>"

  service_account_annotations = {
    "eks.amazonaws.com/role-arn" = aws_iam_role.cert_manager.arn
  }
}

module "letsencrypt_cluster_issuer" {
  source = "github.com/MaterializeInc/materialize-terraform-self-managed//kubernetes/modules/cert-manager/letsencrypt-cluster-issuer?ref=<tag>"

  name_prefix = "my-mz"
  acme_email  = "platform-team@example.com"
  solvers = [
    {
      selector = {
        dnsZones = ["mz.example.com"]
      }
      dns01 = {
        route53 = {
          region       = "us-east-1"
          hostedZoneID = aws_route53_zone.mz.zone_id
        }
      }
    }
  ]

  depends_on = [module.cert_manager]
}
```

## Example: Azure DNS with Azure Workload Identity

The user-assigned managed identity needs the `DNS Zone Contributor` role on
the zone and a federated identity credential for the cluster's OIDC issuer
with subject `system:serviceaccount:cert-manager:cert-manager`. The
`azure.workload.identity/use` pod label opts cert-manager's controller into
the workload identity webhook, and the solver names the identity by client ID.
cert-manager's
[Azure DNS documentation](https://cert-manager.io/docs/configuration/acme/dns01/azuredns/)
covers the Azure side.

```hcl
module "cert_manager" {
  source = "github.com/MaterializeInc/materialize-terraform-self-managed//kubernetes/modules/cert-manager?ref=<tag>"

  pod_labels = {
    "azure.workload.identity/use" = "true"
  }
}

module "letsencrypt_cluster_issuer" {
  source = "github.com/MaterializeInc/materialize-terraform-self-managed//kubernetes/modules/cert-manager/letsencrypt-cluster-issuer?ref=<tag>"

  name_prefix = "my-mz"
  acme_email  = "platform-team@example.com"
  solvers = [
    {
      dns01 = {
        azureDNS = {
          subscriptionID    = var.subscription_id
          resourceGroupName = azurerm_dns_zone.mz.resource_group_name
          hostedZoneName    = azurerm_dns_zone.mz.name
          environment       = "AzurePublicCloud"
          managedIdentity = {
            clientID = azurerm_user_assigned_identity.cert_manager.client_id
          }
        }
      }
    }
  ]

  depends_on = [module.cert_manager]
}
```

## Using the issuer with a Materialize instance

A public CA cannot sign the `cluster.local` names on Materialize's internal
certificates, so pair this issuer with a private one. In the
[`materialize-instance`](../../materialize-instance) module, set `issuer_ref` to
this issuer for the balancer and console certificates, `internal_issuer_ref`
to a private issuer such as the one from
[`self-signed-cluster-issuer`](../../self-signed-cluster-issuer), and list the
public hostnames in `balancerd_extra_dns_names` and `console_extra_dns_names`:

```hcl
module "materialize_instance" {
  source = "github.com/MaterializeInc/materialize-terraform-self-managed//kubernetes/modules/materialize-instance?ref=<tag>"

  # ...

  issuer_ref = {
    name = module.letsencrypt_cluster_issuer.issuer_name
    kind = "ClusterIssuer"
  }
  internal_issuer_ref = {
    name = module.self_signed_cluster_issuer.issuer_name
    kind = "ClusterIssuer"
  }
  balancerd_extra_dns_names = ["sql.mz.example.com"]
  console_extra_dns_names   = ["console.mz.example.com"]
}
```

## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_kubectl"></a> [kubectl](#requirement\_kubectl) | 3.0.1 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_kubectl"></a> [kubectl](#provider\_kubectl) | 3.0.1 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [kubectl_manifest.letsencrypt_cluster_issuer](https://registry.terraform.io/providers/alekc/kubectl/3.0.1/docs/resources/manifest) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_acme_email"></a> [acme\_email](#input\_acme\_email) | Email address the ACME account is registered with. The ACME server sends notices about the account to it. | `string` | n/a | yes |
| <a name="input_acme_server"></a> [acme\_server](#input\_acme\_server) | Directory URL of an ACME server other than Let's Encrypt, for the issuer `<name_prefix>-letsencrypt`. When null, the issuer uses Let's Encrypt staging, or production when acme\_server\_prod is true. | `string` | `null` | no |
| <a name="input_acme_server_prod"></a> [acme\_server\_prod](#input\_acme\_server\_prod) | Issue from Let's Encrypt production, as `<name_prefix>-letsencrypt`, instead of Let's Encrypt staging, as `<name_prefix>-letsencrypt-staging`. Leave it false for the first apply, check that staging issues every certificate, then set it to true; certificates that reference issuer\_name are then reissued from production. Cannot be combined with acme\_server. | `bool` | `false` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | The name prefix to use for Kubernetes resources. | `string` | n/a | yes |
| <a name="input_solvers"></a> [solvers](#input\_solvers) | cert-manager ACME solvers, passed verbatim as the ClusterIssuer's spec.acme.solvers. Each element is one solver object in cert-manager's schema: an http01 or dns01 block and an optional selector. See https://cert-manager.io/docs/configuration/acme/ for the solver fields. | `any` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_issuer_name"></a> [issuer\_name](#output\_issuer\_name) | Name of the ClusterIssuer: `<name_prefix>-letsencrypt-staging` while it uses Let's Encrypt staging, `<name_prefix>-letsencrypt` otherwise. |
