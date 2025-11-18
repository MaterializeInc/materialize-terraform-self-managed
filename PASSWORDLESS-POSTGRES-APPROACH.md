# Passwordless PostgreSQL Authentication Approach

## What We're Trying to Solve

Right now we manage PostgreSQL passwords through Terraform and store them in Kubernetes secrets. This works but has obvious problems - password rotation is painful, secrets management is messy, and we're passing around static credentials. 

What we want is to leverage cloud-native identity federation so pods can authenticate to PostgreSQL using their Kubernetes service account identity. No static passwords, no secret rotation headaches.

## The Common Thread: OIDC-Based Authentication

All three cloud providers (AWS, GCP, Azure) use the same fundamental approach - **OIDC-based identity federation**.

### How It Works

The Kubernetes cluster acts as an OIDC identity provider. When a pod runs with a service account, it gets a JWT token that proves its identity. The cloud provider validates this token and exchanges it for cloud credentials that can generate database authentication tokens.

**Flow:**
```
K8s Service Account → OIDC Token → Cloud IAM validates → Temporary credentials → Database auth token → PostgreSQL
```

**Benefits:**
- No static credentials - everything is dynamically generated
- Automatic token expiration and rotation
- Complete audit trail tied to service accounts
- Principle of least privilege

## Infrastructure Requirements by Cloud Provider

### AWS: IAM Roles for Service Accounts (IRSA)

**What needs to be enabled:**

1. **EKS Cluster**: OIDC provider (enabled by default on new clusters)
2. **RDS Instance**: Set `iam_database_authentication_enabled = true`
3. **IAM Role**: Create role with trust policy for the K8s service account and `rds-db:connect` permission
4. **Kubernetes Service Account**: Add annotation `eks.amazonaws.com/role-arn`
5. **Database User**: Create user and `GRANT rds_iam` role

**Terraform Changes in Our Modules:**
- `aws/modules/database/main.tf` - Enable `iam_database_authentication_enabled`
- `aws/modules/database/iam.tf` - Add IAM role with OIDC trust policy and RDS connect policy
- `aws/modules/eks/outputs.tf` - Export `oidc_provider_arn` and `cluster_oidc_issuer_url`
- `aws/modules/operator/main.tf` - Add IAM role annotation to service account

**Token Details:**
- Tokens expire after **15 minutes** (hard limit)
- Application must generate new token before expiry and reconnect

---

### GCP: Workload Identity

**What needs to be enabled:**

1. **GKE Cluster**: Enable Workload Identity (`workload_identity_config`)
2. **Cloud SQL Instance**: Set database flag `cloudsql.iam_authentication = on`
3. **Google Service Account**: Create GSA with `roles/cloudsql.client` role
4. **Workload Identity Binding**: Link K8s SA to GSA with `roles/iam.workloadIdentityUser`
5. **Kubernetes Service Account**: Add annotation `iam.gke.io/gcp-service-account`
6. **Database User**: Create IAM user with type `CLOUD_IAM_SERVICE_ACCOUNT`

**Terraform Changes in Our Modules:**
- `gcp/modules/gke/main.tf` - Enable Workload Identity
- `gcp/modules/database/main.tf` - Enable IAM auth flag, create GSA, grant Cloud SQL client role, create IAM db user, create workload identity binding
- `gcp/modules/operator/main.tf` - Add GSA annotation to service account

**Token Details:**
- Cloud SQL Proxy or Go Connector handles all token management automatically
- No token expiration handling needed in application code

---

### Azure: Workload Identity Federation

**What needs to be enabled:**

1. **AKS Cluster**: Set `oidc_issuer_enabled = true` and `workload_identity_enabled = true`
2. **PostgreSQL Flexible Server**: Enable `active_directory_auth_enabled = true`
3. **User-Assigned Managed Identity**: Create managed identity for database access
4. **Federated Identity Credential**: Link K8s SA to managed identity with OIDC issuer
5. **Kubernetes Service Account**: Add annotation `azure.workload.identity/client-id`
6. **PostgreSQL AD Admin**: Grant managed identity as AD administrator
7. **Database User**: Create database user/role

**Terraform Changes in Our Modules:**
- `azure/modules/aks/main.tf` - Enable OIDC issuer and workload identity, export OIDC URL
- `azure/modules/database/main.tf` - Enable Entra ID auth, create managed identity, create federated credential, set AD admin
- `azure/modules/operator/main.tf` - Add managed identity annotation to service account

**Token Details:**
- Access tokens expire after **~1 hour**
- Application must generate new token before expiry and reconnect

---

## Connection URL Format Changes

### Current Configuration

Currently, we pass the full database connection URL with embedded password to the Materialize instance via the `metadata_backend_url` variable:

```hcl
# Current format (with static password)
metadata_backend_url = format(
  "postgres://%s:%s@%s/%s?sslmode=require&options=-c%%20statement_timeout%%3D15min",
  db_username,
  urlencode(static_password),  # ← Static password from Terraform
  db_host,
  db_name
)
```

This URL is stored in the Kubernetes secret `<instance-name>-materialize-backend` and read by the Materialize client at startup.

### Passwordless Configuration Options

With IAM authentication, we have two approaches depending on the cloud provider:

#### Option 1: Placeholder Password (AWS/Azure)

For AWS and Azure, the client needs to generate tokens dynamically, so we pass a URL **without** a password or with a placeholder:

```hcl
# Passwordless format - no password field
metadata_backend_url = format(
  "postgres://%s@%s/%s?sslmode=require&options=-c%%20statement_timeout%%3D15min",
  iam_username,  # IAM user (not regular user)
  db_host,
  db_name
)
```

**What the client must do:**
1. Parse the connection URL
2. Extract host, port, username, database name
3. Generate IAM auth token using cloud SDK
4. Inject token as password in the connection parameters
5. Establish connection to PostgreSQL
6. Repeat steps 3-5 when token expires (reconnection required)

#### Option 2: Proxy Connection (GCP)

For GCP with Cloud SQL Proxy, the URL points to the proxy running locally:

```hcl
# GCP with Cloud SQL Proxy
metadata_backend_url = format(
  "postgres://%s@localhost:5432/%s?sslmode=disable&options=-c%%20statement_timeout%%3D15min",
  iam_username,  # Cloud SQL IAM user
  db_name
)
```

**What the client must do:**
1. Parse the connection URL
2. Connect to `localhost:5432` (Cloud SQL Proxy)
3. Proxy handles all authentication transparently
4. No token generation or reconnection needed

---

## Client-Side Requirements

Now here's where it gets interesting. The infrastructure setup above gets us the identity federation, but the application still needs to handle token generation and database connections properly.

### The Challenge: Short-Lived Tokens

Here's the critical part - **database authentication tokens are SHORT-LIVED**:

- **AWS RDS**: Tokens expire after **15 minutes** (this is a hard limit)
- **Azure PostgreSQL**: Access tokens expire after **~1 hour**
- **GCP Cloud SQL**: Handled differently (explained below)

This means the application can't just generate a token once and use it forever. We need to handle token refresh and reconnection.

### AWS Client Implementation

**Required SDK:** `github.com/aws/aws-sdk-go-v2/feature/rds/auth`

**Key Points:**
- Generate auth token using `auth.BuildAuthToken()`
- Use token as password in connection string
- Token expires in 15 minutes - must generate new token and reconnect
- Consider per-connection token generation using `pgx` connection hooks

**Implementation Guides:**
- [AWS: IAM Database Authentication with EKS](https://aws.amazon.com/blogs/containers/using-iam-database-authentication-with-workloads-running-on-amazon-eks/)
- [Community Guide: Kubernetes to RDS Without Passwords](https://notes.hatedabamboo.me/kubernetes-to-rds-without-passwords/)
- [RDS IAM with EKS and Terraform](https://itnext.io/aws-rds-iam-database-authentication-eks-pod-identities-and-terraform-acb2281f4dd4)
- [RDS IAM Authentication Implementation](https://pierreraffa.medium.com/rds-iam-authentication-from-eks-3635056e98af)

### Azure Client Implementation

**Required SDK:** `github.com/Azure/azure-sdk-for-go/sdk/azidentity`

**Key Points:**
- Use `azidentity.NewDefaultAzureCredential()` to get credentials
- Call `GetToken()` with scope `https://ossrdbms-aad.database.windows.net/.default`
- Use token as password in connection string
- Token expires in ~1 hour - must generate new token and reconnect
- SDK caches tokens and refreshes automatically on subsequent `GetToken()` calls
- Username format: `<identity-name>@<server-name>`

**Implementation Guides:**
- [Azure PostgreSQL Entra ID Concepts](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/security-entra-concepts)
- [Azure Access Token Refresh Samples](https://github.com/Azure-Samples/Access-token-refresh-samples)
- [Workload Identity Federation in AKS](https://alexisplantin.fr/workload-identity-federation/)
- [Using Federated Identities in AKS](https://stvdilln.medium.com/using-federated-identities-in-azure-aks-a440feb4a1ce)
- [Entra Authentication to PostgreSQL](https://learn.microsoft.com/en-us/answers/questions/2150312/user-entra-authentication-to-postgres-flexible-ser)

### GCP Client Implementation

**Option 1: Cloud SQL Proxy (Recommended)**
- Run proxy as sidecar container
- Application connects to `localhost:5432` with no password
- Proxy handles all authentication and token refresh automatically

**Option 2: Cloud SQL Go Connector**
- **Required SDK:** `github.com/GoogleCloudPlatform/cloud-sql-go-connector`
- Library handles authentication and token refresh
- Integrates with database drivers (pgx, etc.)

**Implementation Guides:**
- [Connect from GKE using Cloud SQL Proxy](https://docs.cloud.google.com/sql/docs/postgres/connect-instance-kubernetes)
- [Cloud SQL IAM Authentication](https://docs.cloud.google.com/sql/docs/postgres/iam-authentication)
- [Cloud SQL Proxy Overview](https://cloud.google.com/sql/docs/postgres/sql-proxy)
- [Cloud SQL Go Connector](https://github.com/GoogleCloudPlatform/cloud-sql-go-connector)

---

## Connection Pooling Considerations

Short-lived tokens create challenges for traditional connection pooling:

**AWS (15-minute tokens):**
- Refresh entire pool every 10-12 minutes, or
- Generate token per new connection (if connection rate is low), or
- Use custom pool that handles token refresh

**Azure (1-hour tokens):**
- More manageable - refresh pool every 45-50 minutes
- Coordinate pool refresh with token expiry

**GCP:**
- No pooling issues - proxy/connector handles everything

## Summary

**Infrastructure Work (Our Responsibility):**
- Enable OIDC/Workload Identity on Kubernetes clusters
- Enable IAM authentication on database instances
- Create cloud IAM identities (roles/service accounts/managed identities)
- Link Kubernetes service accounts to cloud identities
- Create IAM database users

**Application Work (Application Team Responsibility):**
- Integrate cloud SDK to generate database auth tokens
- Handle token expiration and reconnection (AWS/Azure)
- Implement token refresh strategy (periodic refresh or per-connection)
- Error handling for authentication failures

**Key Differences:**
- **GCP** is easiest - proxy handles everything
- **AWS** requires most work - 15-minute token lifetime demands careful handling
- **Azure** is moderate - 1-hour tokens are more forgiving but still need reconnection logic

---

## References

### AWS
- [IAM Database Authentication with EKS](https://aws.amazon.com/blogs/containers/using-iam-database-authentication-with-workloads-running-on-amazon-eks/)
- [RDS IAM Authentication Guide](https://aws.amazon.com/blogs/database/using-iam-authentication-to-connect-with-pgadmin-amazon-aurora-postgresql-or-amazon-rds-for-postgresql/)
- [Kubernetes to RDS Without Passwords](https://notes.hatedabamboo.me/kubernetes-to-rds-without-passwords/)
- [RDS IAM with EKS and Terraform](https://itnext.io/aws-rds-iam-database-authentication-eks-pod-identities-and-terraform-acb2281f4dd4)
- [RDS IAM from EKS Implementation](https://pierreraffa.medium.com/rds-iam-authentication-from-eks-3635056e98af)

### GCP
- [Connect from GKE using IAM](https://docs.cloud.google.com/sql/docs/postgres/connect-instance-kubernetes)
- [Cloud SQL IAM Authentication](https://docs.cloud.google.com/sql/docs/postgres/iam-authentication)
- [Cloud SQL Proxy](https://cloud.google.com/sql/docs/postgres/sql-proxy)
- [Cloud SQL Go Connector](https://github.com/GoogleCloudPlatform/cloud-sql-go-connector)

### Azure
- [PostgreSQL Entra ID Concepts](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/security-entra-concepts)
- [Access Token Refresh Samples](https://github.com/Azure-Samples/Access-token-refresh-samples)
- [Workload Identity Federation in AKS](https://alexisplantin.fr/workload-identity-federation/)
- [Federated Identities in AKS](https://stvdilln.medium.com/using-federated-identities-in-azure-aks-a440feb4a1ce)
- [Entra Auth to PostgreSQL Q&A](https://learn.microsoft.com/en-us/answers/questions/2150312/user-entra-authentication-to-postgres-flexible-ser)
