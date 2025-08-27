# Azure Storage Module

This module creates an Azure Storage Account and Container for Materialize, along with SAS token management via Azure Key Vault.

## Prerequisites

This module requires Python 3 and specific Azure SDK packages to be installed in the environment where Terraform runs.

### Install Python Dependencies

```bash
pip install -r requirements.txt
```

Or install individually:
```bash
pip install azure-identity azure-storage-blob azure-mgmt-storage azure-keyvault-secrets
```

### Alternative Deployment Options

- **Azure Cloud Shell**: Already has all required Azure SDK packages pre-installed

### Environment Setup Example

```bash
# For local development
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt

# Run Terraform
terraform init
terraform plan
terraform apply
```
