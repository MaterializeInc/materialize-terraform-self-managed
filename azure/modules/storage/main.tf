resource "azurerm_storage_account" "materialize" {
  name                = replace("${var.prefix}stg${random_string.unique.result}", "-", "")
  resource_group_name = var.resource_group_name
  location            = var.location
  # TODO: revisit to make sure we are using best set of values for storage account tier, replication type, and kind
  # and what other options user have to configure this.
  account_tier             = "Premium"
  account_replication_type = "LRS"
  account_kind             = "BlockBlobStorage"

  dynamic "network_rules" {
    for_each = length(var.subnets) == 0 ? [] : ["has_subnets"]
    content {
      # TODO: Default action should be Deny, and then we can add the subnets to the allow list.
      default_action             = "Allow"
      bypass                     = ["AzureServices"]
      virtual_network_subnet_ids = var.subnets
    }
  }

  tags = var.storage_account_tags
}

resource "azurerm_storage_container" "materialize" {
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.materialize.id
  container_access_type = var.container_access_type
}

resource "random_string" "unique" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_role_assignment" "storage_blob_contributor" {
  scope                = azurerm_storage_account.materialize.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.workload_identity_principal_id
}

# Federated identity credential that establishes trust between the Kubernetes service account
# and the Azure workload identity for storage access (similar to GCP Workload Identity or AWS IRSA)
resource "azurerm_federated_identity_credential" "materialize_storage" {
  name                = "${var.prefix}-storage-credential"
  resource_group_name = var.resource_group_name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.oidc_issuer_url
  parent_id           = var.workload_identity_id
  subject             = "system:serviceaccount:${var.service_account_namespace}:${var.service_account_name}"
}
