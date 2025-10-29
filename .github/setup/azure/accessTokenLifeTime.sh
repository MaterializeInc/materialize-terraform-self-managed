
#!/bin/bash

# Exit early on error/unset var/pipe failure
set -euo pipefail

# 1. Create a 4-hour token lifetime policy and capture the policy ID
POLICY_RESPONSE=$(az rest --method POST \
  --url "https://graph.microsoft.com/v1.0/policies/tokenLifetimePolicies" \
  --headers "Content-Type=application/json" \
  --body '{
    "definition": ["{\"TokenLifetimePolicy\":{\"Version\":1,\"AccessTokenLifetime\":\"04:00:00\"}}"],
    "displayName": "ExtendedAccessTokenPolicy",
    "isOrganizationDefault": false
  }')

# 2. Extract policy ID and get application ID
POLICY_ID=$(echo $POLICY_RESPONSE | jq -r '.id')
APP_ID=$(az ad app list --display-name "mz-self-managed-github-actions" --query "[0].id" -o tsv)

echo "Policy ID: $POLICY_ID"
echo "Application ID: $APP_ID"

# 3. Assign policy to application
az rest --method POST \
  --url "https://graph.microsoft.com/v1.0/applications/${APP_ID}/tokenLifetimePolicies/\$ref" \
  --headers "Content-Type=application/json" \
  --body "{\"@odata.id\": \"https://graph.microsoft.com/v1.0/policies/tokenLifetimePolicies/${POLICY_ID}\"}"

echo "✅ Token lifetime policy applied successfully!"
