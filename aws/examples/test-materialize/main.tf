
provider "aws" {
  region  = var.region
  profile = var.profile
}

provider "kubernetes" {
  host                   = var.cluster_endpoint
  cluster_ca_certificate = base64decode(var.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = var.cluster_endpoint
    cluster_ca_certificate = base64decode(var.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
    }
  }
}

module "openebs" {
  source = "../../../kubernetes/modules/openebs"

  openebs_namespace    = var.openebs_namespace
  openebs_version      = var.openebs_chart_version
  install_openebs      = var.enable_disk_support
  install_openebs_crds = var.install_openebs_crds
}

module "certificates" {
  source = "../../../kubernetes/modules/certificates"

  install_cert_manager           = var.install_cert_manager
  cert_manager_install_timeout   = var.cert_manager_install_timeout
  cert_manager_chart_version     = var.cert_manager_chart_version
  use_self_signed_cluster_issuer = var.install_materialize_instance
  cert_manager_namespace         = var.cert_manager_namespace
  name_prefix                    = var.name_prefix
}

module "operator" {
  source = "../../modules/operator"

  name_prefix         = var.name_prefix
  aws_region          = var.region
  operator_namespace  = var.operator_namespace
  aws_account_id      = data.aws_caller_identity.current.account_id
  enable_disk_support = var.enable_disk_support

  use_self_signed_cluster_issuer = var.install_materialize_instance
}

module "storage" {
  source                   = "../../modules/storage"
  name_prefix              = var.name_prefix
  bucket_lifecycle_rules   = var.bucket_lifecycle_rules
  bucket_force_destroy     = var.bucket_force_destroy
  enable_bucket_versioning = var.enable_bucket_versioning
  enable_bucket_encryption = var.enable_bucket_encryption

  # IRSA configuration
  oidc_provider_arn         = var.oidc_provider_arn
  cluster_oidc_issuer_url   = var.cluster_oidc_issuer_url
  service_account_namespace = var.instance_namespace
  service_account_name      = var.instance_name

  tags = var.tags
}

module "materialize_instance" {
  count = var.install_materialize_instance ? 1 : 0

  source               = "../../../kubernetes/modules/materialize-instance"
  instance_name        = var.instance_name
  instance_namespace   = var.instance_namespace
  metadata_backend_url = local.metadata_backend_url
  persist_backend_url  = local.persist_backend_url

  # The password for the external login to the Materialize instance
  external_login_password_mz_system = var.external_login_password_mz_system

  # AWS IAM role annotation for service account
  service_account_annotations = {
    "eks.amazonaws.com/role-arn" = module.storage.materialize_s3_role_arn
  }

  depends_on = [
    module.storage,
    module.certificates,
    module.operator,
    module.openebs,
  ]
}

module "materialize_nlb" {
  count = var.install_materialize_instance ? 1 : 0

  source = "../../modules/nlb"

  instance_name                    = var.instance_name
  name_prefix                      = var.name_prefix
  namespace                        = var.instance_namespace
  subnet_ids                       = var.subnet_ids
  enable_cross_zone_load_balancing = var.enable_cross_zone_load_balancing
  vpc_id                           = var.vpc_id
  mz_resource_id                   = module.materialize_instance[0].instance_resource_id

  depends_on = [
    module.materialize_instance
  ]
}

locals {

  metadata_backend_url = format(
    "postgres://%s:%s@%s/%s?sslmode=require",
    var.database_username,
    urlencode(var.database_password),
    var.database_endpoint,
    var.database_name
  )

  persist_backend_url = format(
    "s3://%s/system:serviceaccount:%s:%s",
    module.storage.bucket_name,
    var.instance_namespace,
    var.instance_name
  )
}

data "aws_caller_identity" "current" {}
