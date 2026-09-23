# Nexus APK pull-through cache — Terraform module

Configures Sonatype Nexus Repository Manager as a pull-through cache for
Chainguard APK package repositories using the `sonatyperepo` Terraform
provider.

The native Alpine repository type in Nexus does not support Chainguard's APK
repositories, so this module uses raw proxy repositories instead. Two proxies
(one for packages, one for the index) sit behind a routing-rule pair and a
group repository. Clients point `apk` at the group URL.

```
apk client
    └─▶ chainguard-apk (raw group)
            ├─▶ chainguard-apk-packages (raw proxy, BLOCK APKINDEX, TTL = ∞)
            └─▶ chainguard-apk-index    (raw proxy, ALLOW APKINDEX only, TTL = 15 min)
                        │
                        └─▶ https://apk.cgr.dev/<organization>
```

## Prerequisites

| Requirement | Notes |
|---|---|
| Terraform ≥ 1.3 | `brew install terraform` |
| Nexus Repository Manager ≥ 3.94 | [Docker quickstart](#local-nexus-quickstart) below |
| `chainctl` | [Install guide](https://edu.chainguard.dev/chainguard/chainctl-usage/how-to-install-chainctl/) |
| Chainguard `owner` role | Required to create the pull token (`role_bindings.create`) |

### Local Nexus quickstart

```bash
docker run -d -p 8081:8081 --name nexus sonatype/nexus3
# Wait ~60 s for startup, then retrieve the initial admin password:
docker exec nexus cat /nexus-data/admin.password
# Log in at http://localhost:8081 as 'admin' with that password.
```

## Generating a Chainguard pull token

The proxies authenticate to Chainguard with a pull token scoped to the
`apk.pull` role. Generate one with `chainctl`:

```bash
chainctl auth pull-token --repository=apk
```

The output contains a `Username` (identity ID) and `Password` (token). Keep
both — you will need them as input variables.

## Passing credentials

Never put credentials in `.tf` files or commit them to version control. Use
one of the two approaches below.

### Option A — Environment variables (recommended)

The `sonatyperepo` provider reads Nexus credentials from its own environment
variables, so they never need to appear in Terraform configuration at all.
Terraform reads the remaining variables via the `TF_VAR_` prefix.

```bash
# Nexus — consumed directly by the provider
# https://registry.terraform.io/providers/sonatype-nexus-community/sonatyperepo/latest/docs
export NXRM_SERVER_URL="http://localhost:8081"
export NXRM_SERVER_USERNAME="admin"
export NXRM_SERVER_PASSWORD="<nexus-admin-password>"

# Chainguard pull token
# https://developer.hashicorp.com/terraform/language/values/variables#environment-variables
export TF_VAR_chainguard_organization="example.org"
export TF_VAR_chainguard_pull_token_username="<identity-id>"
export TF_VAR_chainguard_pull_token_password="<pull-token>"
```

With these set, `nexus_url`, `nexus_username`, and `nexus_password` in
`variables.tf` are unused and can be omitted from the provider block in
`providers.tf`.

### Option B — `terraform.tfvars` (local development only)

Create a `terraform.tfvars` file and ensure it is never committed:

```bash
echo "terraform.tfvars" >> .gitignore
```

```hcl
# terraform.tfvars — keep out of version control
nexus_url                          = "http://localhost:8081"
nexus_username                     = "admin"
nexus_password                     = "<nexus-admin-password>"
chainguard_organization            = "example.org"
chainguard_pull_token_username     = "<identity-id>"
chainguard_pull_token_password     = "<pull-token>"
```

Terraform loads this file automatically. The risk over Option A is accidental
commits; if your workflow has a CI step that could expose the file, prefer
environment variables.

## Deployment

```bash
terraform init
terraform plan
terraform apply
```

On success, the output `group_repository_url` is the URL to use in
`/etc/apk/repositories`.

## Known gaps

### Preserve encoded characters in URLs — manual step required

After `terraform apply`, you must enable **Preserve encoded characters in
URLs** for both proxy repositories in the Nexus UI. The `sonatyperepo`
Terraform provider does not yet expose this setting.

**Why it matters:** `apk.cgr.dev` redirects `.apk` requests to Cloudflare R2
presigned URLs. The signature covers percent-encoded characters (`%2B`, `%2F`,
`%3D`). Nexus's default URL normalization decodes them before forwarding the
request, which invalidates the signature and produces HTTP 403 errors.

**Steps:**

1. Open Nexus at `<NEXUS_URL>` and log in as an administrator.
2. Go to **Settings → Repository → Repositories**.
3. Click **chainguard-apk-packages**. Under the **HTTP** section, check
   **Preserve encoded characters in URLs**. Save.
4. Repeat for **chainguard-apk-index**.

## Input variables

| Variable | Default | Description |
|---|---|---|
| `nexus_url` | — | Nexus base URL (e.g. `http://localhost:8081`) |
| `nexus_username` | `admin` | Nexus admin username |
| `nexus_password` | — | Nexus admin password |
| `chainguard_organization` | — | Org name as shown in the Chainguard Console |
| `chainguard_pull_token_username` | — | `Username` from `chainctl auth pull-token` |
| `chainguard_pull_token_password` | — | `Password` from `chainctl auth pull-token` |
| `blob_store_name` | `default` | Nexus blob store for all created repositories |
| `index_max_age_minutes` | `15` | Cache TTL for `APKINDEX.tar.gz` in minutes |

## Outputs

| Output | Description |
|---|---|
| `group_repository_url` | Point `/etc/apk/repositories` at this URL |
| `packages_proxy_url` | Direct URL of the packages proxy (debugging) |
| `index_proxy_url` | Direct URL of the index proxy (debugging) |

## Security best practices

**Credentials**
- Use environment variables (Option A) so secrets never touch disk in the
  Terraform working directory.
- In CI/CD, inject secrets via your platform's secret store (GitHub Actions
  secrets, GitLab CI variables, etc.) rather than storing them in repository
  files.
- For production, source credentials at plan time from a secrets manager
  (HashiCorp Vault, AWS Secrets Manager, GCP Secret Manager) using a Terraform
  data source instead of input variables.
- Pull tokens are scoped to the `apk.pull` role — they cannot push packages or
  modify your Chainguard organization. Rotate them if they are exposed.

**State file**
- `terraform.tfstate` contains the pull token credentials in plaintext.
  Store remote state in an encrypted backend (S3 + KMS, GCS, Terraform Cloud)
  rather than committing the local state file.
- Add `terraform.tfstate*` and `.terraform/` to `.gitignore`.

**Nexus**
- The Nexus admin password used here has full administrative access. Consider
  creating a dedicated Nexus user with only the permissions required to manage
  repositories, and use that account instead.
- If Nexus is not on localhost, ensure it is behind TLS and use an `https://`
  URL so credentials are not sent in plaintext.

## Resources created

| Type | Name |
|---|---|
| `sonatyperepo_routing_rule` | `chainguard-apk-block-index` |
| `sonatyperepo_routing_rule` | `chainguard-apk-only-index` |
| `sonatyperepo_repository_raw_proxy` | `chainguard-apk-packages` |
| `sonatyperepo_repository_raw_proxy` | `chainguard-apk-index` |
| `sonatyperepo_repository_raw_group` | `chainguard-apk` |
