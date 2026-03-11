# Infrastructure Testing Workflows

## Workflow Structure

```
pr.yml (pull_request)
  └── lint.yml
  └── ci-success (gates on lint)

merge_queue.yml (merge_group)
  └── lint.yml
  └── test-aws.yml
  └── test-gcp.yml
  └── test-azure.yml
  └── ci-success (gates on all above)
```

## Merge Queue Integration

Infrastructure tests **integrate with GitHub's merge queue** to ensure only approved, tested code reaches `main`.

### How It Works

1. **Create PR** - `pr.yml` runs lint checks, `ci-success` passes when lint passes
2. **Get approval** - PR enters merge queue automatically
3. **Tests run** - `merge_queue.yml` runs full infrastructure tests (AWS, GCP, Azure)
4. **Auto-merge** - When `ci-success` passes, code merges to `main`
5. **Manual trigger** - Use `gh workflow run test-<cloud>.yml` if needed

### PR vs Merge Queue Behavior

| Event | Workflow | What Runs | ci-success gates on |
|-------|----------|-----------|---------------------|
| `pull_request` | `pr.yml` | Lint only | Lint |
| `merge_group` | `merge_queue.yml` | Lint + all cloud tests | Lint + AWS + GCP + Azure |
| `workflow_dispatch` | `test-*.yml` | Individual cloud test | N/A |

### What Gets Tested (Merge Queue Only)

| Path Changes | Tests Triggered |
|-------------|----------------|
| `*/modules/**/*.tf`, `kubernetes/modules/**/*.{tf,yaml,yml}` | Relevant cloud tests |
| `test/aws/**/*.{go,tf}`, `test/gcp/**/*.{go,tf}`, `test/azure/**/*.{go,tf}` | Relevant cloud tests |
| `test/utils/**`, `test/shared/**`, `test/*.go` | **All cloud tests** |
| `*/examples/**`, `README.md`, `.env`, docs | No tests (skipped) |

### Features

- **Fast PR feedback** - PRs only run lint, cloud tests run in merge queue
- **Single required check** - Only `ci-success` needs to be required in branch protection
- **Granular path filtering** - Cloud tests skip when no relevant files changed
- **Smart cloud detection** - Tests only affected clouds, or all clouds for shared changes
- **Parallel cloud testing** - AWS/GCP/Azure run simultaneously in merge queue

## Setup Requirements

**Branch Protection:**
- Enable merge queue for `main` branch
- Require PR approvals
- Add required status check: `PR / ci-success`

**Merge Queue:**
- Add required status check: `Merge Queue / ci-success`


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
