# Infrastructure Testing Workflows

## 🛡️ **Merge Queue Integration**

Infrastructure tests **integrate with GitHub's merge queue** to ensure only approved, tested code reaches `main`.

### **How It Works**
1. **Create PR** → Request review
2. **Get approval** → PR enters merge queue automatically
3. **Tests run** → Only affected cloud providers tested (smart path filtering)
4. **Auto-merge** → When tests pass, code merges to `main`
5. **Manual trigger** → Use `gh workflow run test-<cloud>.yml` if needed


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
- ✅ **Merge queue integration** - Automatic testing on approved PRs
- ✅ **Conflict resolution** - Auto-retests when merge conflicts occur
- ✅ **Parallel cloud testing** - AWS/GCP/Azure run simultaneously when needed

## **Setup Requirements**

**Branch Protection + Merge Queue:**
- Enable merge queue for `main` branch
- Require PR approvals (dismisses stale approvals)  
- Add required status checks: `AWS Tests`, `GCP Tests`, `Azure Tests`


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

## **Manual Testing**

```bash
# Run individual cloud tests manually (for debugging/testing)
gh workflow run test-aws.yml --ref your-branch
gh workflow run test-gcp.yml --ref your-branch  
gh workflow run test-azure.yml --ref your-branch

# Note: Manual runs bypass merge queue but still require proper authentication
# Production merges should always go through the merge queue process
```
