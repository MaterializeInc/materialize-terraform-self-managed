# Azure Storage Module

This module creates an Azure Storage Account and Container for Materialize with Azure Workload Identity integration for secure, credential-free access.

## Features

- **Azure Storage Account**: Premium BlockBlobStorage for optimal performance
- **Storage Container**: Dedicated container for Materialize data
- **Workload Identity Integration**: Federated identity credential for Kubernetes service account authentication
- **Role-Based Access**: Storage Blob Data Contributor role assignment for the workload identity

## Authentication

This module uses Azure Workload Identity to provide secure, credential-free access to Azure Blob Storage. The module creates:

1. **Federated Identity Credential**: Links the Kubernetes service account to the Azure workload identity
2. **Role Assignment**: Grants Storage Blob Data Contributor permissions to the workload identity
3. **OIDC Trust**: Establishes trust between AKS cluster and Azure AD

No SAS tokens or storage account keys are required for authentication.
