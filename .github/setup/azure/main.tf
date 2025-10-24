# Azure AD Application and Service Principal for GitHub Actions OIDC
# https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-azure
#
# Note: Token lifetime is controlled by Azure AD's default policy (60 minutes).
# To extend token lifetime, you would need to create a TokenLifetimePolicy using accessTokenLifeTime.sh script after applying this terraform configuration
resource "azuread_application" "github_actions" {
  display_name = "mz-self-managed-github-actions"
  description  = "Application for GitHub Actions CI/CD with OIDC authentication"

  # Optional: Enable service principal creation
  owners = [data.azuread_client_config.current.object_id]
}

# Service Principal for the application
resource "azuread_service_principal" "github_actions" {
  client_id                    = azuread_application.github_actions.client_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.current.object_id]

  tags = ["GitHubActions", "MaterializeTerraform", "OIDC"]
}

# Federated Identity Credentials for GitHub Actions OIDC
# Azure requires specific branch patterns rather than wildcards

# For main branch
resource "azuread_application_federated_identity_credential" "github_actions_main" {
  application_id = azuread_application.github_actions.id
  display_name   = "mz-github-actions-oidc-main"
  description    = "Federated credential for GitHub Actions on main branch"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repository}:ref:refs/heads/main"
}

# For pull requests
resource "azuread_application_federated_identity_credential" "github_actions_pr" {
  application_id = azuread_application.github_actions.id
  display_name   = "mz-github-actions-oidc-pr"
  description    = "Federated credential for GitHub Actions on pull requests"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repository}:pull_request"
}

# Get current Azure AD configuration
data "azuread_client_config" "current" {}

# Get current subscription
data "azurerm_client_config" "current" {}


# Principle of Least Privilege: Minimal role assignments based on fixture requirements
# All role names verified against Azure CLI output

# For AKS cluster management
resource "azurerm_role_assignment" "github_actions_aks_contributor" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Azure Kubernetes Service Contributor Role"
  principal_id         = azuread_service_principal.github_actions.object_id
}

# For networking (VNets, subnets)
resource "azurerm_role_assignment" "github_actions_network_contributor" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Network Contributor"
  principal_id         = azuread_service_principal.github_actions.object_id
}

# For PostgreSQL database management
resource "azurerm_role_assignment" "github_actions_sql_contributor" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "SQL DB Contributor"
  principal_id         = azuread_service_principal.github_actions.object_id
}

# For storage account management
resource "azurerm_role_assignment" "github_actions_storage_contributor" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Storage Account Contributor"
  principal_id         = azuread_service_principal.github_actions.object_id
}

# For blob storage operations
resource "azurerm_role_assignment" "github_actions_storage_blob" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.github_actions.object_id
}

# For workload identity management (Azure AD managed identities)
resource "azurerm_role_assignment" "github_actions_managed_identity_contributor" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Managed Identity Contributor"
  principal_id         = azuread_service_principal.github_actions.object_id
}

# For Azure Monitor and Log Analytics (if enabled)
# resource "azurerm_role_assignment" "github_actions_log_analytics_contributor" {
#   scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
#   role_definition_name = "Log Analytics Contributor"
#   principal_id         = azuread_service_principal.github_actions.object_id
# }

# For resource group creation/management (required by networking fixture)
# Note: No specific "Resource Group Contributor" role exists - using generic Contributor
# resource "azurerm_role_assignment" "github_actions_contributor" {
#   scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
#   role_definition_name = "Contributor"
#   principal_id         = azuread_service_principal.github_actions.object_id
# }
