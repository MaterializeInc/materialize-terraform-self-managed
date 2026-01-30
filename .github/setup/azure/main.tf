# Azure AD Application and Service Principal for GitHub Actions OIDC
# https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-azure
#
# Note: Token lifetime is controlled by Azure AD's default policy (60 minutes).
# To extend token lifetime, you would need to create a TokenLifetimePolicy using accessTokenLifeTime.sh script after applying this terraform configuration

# TODO: Fix Azure federated identity credential for merge queue authentication
#       - Add environment-based credential or specific merge queue subject pattern
#       - Subject pattern needed: repo:MaterializeInc/materialize-terraform-self-managed:environment:production
#       - Or alternative: repo:MaterializeInc/materialize-terraform-self-managed:merge_group(verify if this works, if it does then prefer this)

# TODO: After permissions issue is fixed:
#       1. Test terraform configuration and apply federated identity credential changes
#       2. Update Azure workflow to use environment-based authentication (add environment: production to job)
#       3. Re-enable merge_group trigger in .github/workflows/test-azure.yml
#       4. Validate merge queue authentication works with new federated identity credential

# TODO: Investigate and resolve Azure permissions issues preventing terraform apply
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

# Get built-in role definitions for ABAC conditions
data "azurerm_role_definition" "owner" {
  name  = "Owner"
  scope = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
}

data "azurerm_role_definition" "user_access_administrator" {
  name  = "User Access Administrator"
  scope = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
}

data "azurerm_role_definition" "rbac_administrator" {
  name  = "Role Based Access Control Administrator"
  scope = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
}


# Principle of Least Privilege: Minimal role assignments based on fixture requirements
# Refer roles from https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles to follow the principle of least privilege
# For AKS cluster management
# resource "azurerm_role_assignment" "github_actions_aks_contributor" {
#   scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
#   role_definition_name = "Azure Kubernetes Service Contributor Role"
#   principal_id         = azuread_service_principal.github_actions.object_id
# }

# # For networking (VNets, subnets)
# resource "azurerm_role_assignment" "github_actions_network_contributor" {
#   scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
#   role_definition_name = "Network Contributor"
#   principal_id         = azuread_service_principal.github_actions.object_id
# }

# # For PostgreSQL database management
# resource "azurerm_role_assignment" "github_actions_sql_contributor" {
#   scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
#   role_definition_name = "SQL DB Contributor"
#   principal_id         = azuread_service_principal.github_actions.object_id
# }

# # For storage account management
# resource "azurerm_role_assignment" "github_actions_storage_contributor" {
#   scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
#   role_definition_name = "Storage Account Contributor"
#   principal_id         = azuread_service_principal.github_actions.object_id
# }

# # For blob storage operations
# resource "azurerm_role_assignment" "github_actions_storage_blob" {
#   scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
#   role_definition_name = "Storage Blob Data Contributor"
#   principal_id         = azuread_service_principal.github_actions.object_id
# }

# # For workload identity management (Azure AD managed identities)
# resource "azurerm_role_assignment" "github_actions_managed_identity_contributor" {
#   scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
#   role_definition_name = "Managed Identity Contributor"
#   principal_id         = azuread_service_principal.github_actions.object_id
# }

# For Azure Monitor and Log Analytics (if enabled)
# resource "azurerm_role_assignment" "github_actions_log_analytics_contributor" {
#   scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
#   role_definition_name = "Log Analytics Contributor"
#   principal_id         = azuread_service_principal.github_actions.object_id
# }

# Facing issues with the custom role definition, so using the built-in Contributor role instead. Because I cannot create custom role definitions.
# For resource group creation/management (required by networking fixture)
# Note: No specific "Resource Group Contributor" role exists - using generic Contributor
# resource "azurerm_role_assignment" "github_actions_contributor" {
#   scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
#   role_definition_name = "Contributor"
#   principal_id         = azuread_service_principal.github_actions.object_id
# }

# resource "azurerm_role_definition" "resource_group_manager" {
#   name        = "GitHub Actions Resource Group Manager"
#   scope       = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
#   description = "Minimal permissions for resource group creation and management"

#   permissions {
#     actions = [
#       # Core resource group operations (absolutely minimal)
#       "Microsoft.Resources/subscriptions/resourcegroups/read",
#       "Microsoft.Resources/subscriptions/resourcegroups/write", 
#       "Microsoft.Resources/subscriptions/resourcegroups/delete"
#     ]
#     not_actions = []
#   }

#   assignable_scopes = [
#     "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
#   ]
# }

# # Assign the custom resource group role not able to perform this getting authz error
# resource "azurerm_role_assignment" "github_actions_resource_group_manager" {
#   scope              = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
#   role_definition_id = azurerm_role_definition.resource_group_manager.role_definition_resource_id
#   principal_id       = azuread_service_principal.github_actions.object_id
# }

resource "azurerm_role_assignment" "github_actions_contributor" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.github_actions.object_id
}

# RBAC Administrator role for AKS role assignments
# AKS modules need to assign network roles to managed identities and subnets
# Commented out due to ABAC restrictions - use more specific roles instead
# Maybe make it more restrictive to only assing
# ---> Network Contributor and Storage Blob Data Contributor since we only assign those in az modules
resource "azurerm_role_assignment" "github_actions_rbac_admin" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = azuread_service_principal.github_actions.object_id

  # ABAC condition to block assignment of high-privilege roles
  # Allows assignment of any role EXCEPT: Owner, User Access Administrator, RBAC Administrator
  # Using data sources to get role definition IDs dynamically instead of hardcoding
  condition         = <<-EOT
    (
      (!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) 
      OR 
      (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAllOfAllValues:StringNotEquals {
        '${data.azurerm_role_definition.owner.id}', 
        '${data.azurerm_role_definition.user_access_administrator.id}', 
        '${data.azurerm_role_definition.rbac_administrator.id}'
      })
    ) 
    AND 
    (
      (!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) 
      OR 
      (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAllOfAllValues:StringNotEquals {
        '${data.azurerm_role_definition.owner.id}', 
        '${data.azurerm_role_definition.user_access_administrator.id}', 
        '${data.azurerm_role_definition.rbac_administrator.id}'
      })
    )
  EOT
  condition_version = "2.0"
}
