# Infrastructure Testing Workflows

## 🛡️ **Approval-Gated Testing**

Infrastructure tests **require PR approval** to prevent accidental resource provisioning and manage costs.

### **How It Works**
1. **Create PR** → No tests run initially
2. **Get approval** → Tests run automatically  
3. **Push changes** → Tests re-run automatically (if PR approved)
4. **Manual trigger** → Use `gh workflow run test-<cloud>.yml` if needed


### **What Gets Tested**

| Path Changes | Tests Triggered |
|-------------|----------------|
| `*/modules/**/*.tf`, `kubernetes/modules/**/*.{tf,yaml,yml}` | ✅ Relevant cloud tests |
| `test/aws/**/*.{go,tf}`, `test/gcp/**/*.{go,tf}`, `test/azure/**/*.{go,tf}` | ✅ Relevant cloud tests |
| `test/utils/**`, `test/shared/**`, `test/*.go` | ✅ **All cloud tests** |
| `*/examples/**`, `README.md`, `.env`, docs | ❌ No tests |

### **Features**
- ✅ **Granular path filtering** - Only tests infrastructure changes (excludes docs/README)
- ✅ **Smart cloud detection** - Tests only affected clouds, or all clouds for shared changes
- ✅ **Race condition prevention** - One workflow per PR
- ✅ **Parallel cloud testing** - AWS/GCP/Azure run simultaneously  
- ✅ **Auto-retest** - New pushes trigger tests if PR approved

## **Setup Requirements**

**Repository Secrets:**
```
MATERIALIZE_LICENSE_KEY
AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID  
GCP_WORKLOAD_IDENTITY_PROVIDER, GCP_SERVICE_ACCOUNT_EMAIL
```

**Repository Variables:**
```
GA_AWS_IAM_ROLE
TF_TEST_S3_BUCKET, TF_TEST_S3_REGION, TF_TEST_S3_PREFIX
GOOGLE_PROJECT, AWS_REGION
```

## **Manual Override**

```bash
# Run tests without approval (requires repo access)
gh workflow run test-aws.yml --ref your-branch
gh workflow run test-gcp.yml --ref your-branch  
gh workflow run test-azure.yml --ref your-branch
```
