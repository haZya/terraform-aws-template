# Terraform AWS template for multi-account and multi-regional deployments

This repo uses separate Terraform root modules per environment, split into global/shared and regional stacks. Application roots are intentionally scaffolded; add your global resources to `envs/*/global`, regional resources to `modules/app`, and expose any useful values through the committed empty `outputs.tf` files.

```text
bootstrap/
  state/                    # local-state setup for the shared Terraform state bucket
  accounts/staging/         # local-state setup for the staging GitHub Actions role
  accounts/prod/            # local-state setup for the production GitHub Actions role
  modules/                  # bootstrap-only reusable modules
envs/dev/global/            # local CLI testing for dev shared/global resources
envs/dev/regional/          # local CLI testing for dev regional app resources
envs/staging/global/        # GitHub-deployed staging shared/global resources
envs/staging/regional/      # GitHub-deployed staging regional app resources
envs/prod/global/           # GitHub-deployed production shared/global resources
envs/prod/regional/         # GitHub-deployed production regional app resources
modules/app/                # reusable regional app infrastructure
```

## Prerequisites

Use Terraform `>= 1.15` locally and in CI. This template uses the S3 backend native lock file (`use_lockfile = true`) instead of a DynamoDB lock table.

You need AWS credentials for the bootstrap state account, staging account, production account, and optional local dev account. The examples assume AWS shared config profiles named `shared-state`, `staging-admin`, `prod-admin`, and `dev`, but you can use any profiles that match your accounts.

Create GitHub environments named `staging` and `production` before enabling deployments. Add required reviewers to `production`; this is the approval gate that pauses push-based promotion before production applies.

Commit `.terraform.lock.hcl` files for each root. Do not commit `.terraform/`, real `terraform.tfvars`, bootstrap-generated `backend.tf`, `backend.hcl`, plans, or state files.

## Stack Boundaries

Put resources that are deployed once per environment in `global/`. Examples: IAM, Route 53 zones, CloudFront, Global Accelerator, shared KMS keys, or anything that should not be recreated once per region.

Put resources that are deployed once per region in `regional/`.

Global and regional stacks use separate state files. Deploy global first when regional resources depend on shared resources. Destroy regional first, then global.

## Bootstrap Order

Bootstrap roots intentionally do not commit a live `backend.tf` file. The first bootstrap run must initialize with `-backend=false` because the remote state bucket does not exist yet. That first run uses local state. Use a fixed state account ID up front so the future state bucket name is known before the bucket exists.

Do not copy `backend.tf.example` before the first local bootstrap apply. If you previously initialized a bootstrap root with a backend block and need to restart the local bootstrap flow, delete only that root's generated `backend.tf` and `.terraform/` directory, then rerun `terraform init -backend=false`. Do not delete `terraform.tfstate` unless you intentionally want to discard local bootstrap state.

With the default convention, the bucket name is:

```text
<app_name>-terraform-state-<shared-state-account-id>
```

For example:

```text
example-app-terraform-state-000000000000
```

Create the GitHub OIDC deployment roles first. IAM policies can reference the future state bucket ARN before the bucket exists.

PowerShell:

```powershell
Copy-Item bootstrap/accounts/staging/terraform.tfvars.example bootstrap/accounts/staging/terraform.tfvars
```

sh/bash/zsh:

```sh
cp bootstrap/accounts/staging/terraform.tfvars.example bootstrap/accounts/staging/terraform.tfvars
```

### Bootstrap Staging

```sh
terraform -chdir=bootstrap/accounts/staging init -backend=false
terraform -chdir=bootstrap/accounts/staging apply
terraform -chdir=bootstrap/accounts/staging output github_actions_role_arn
```

PowerShell:

```powershell
Copy-Item bootstrap/accounts/prod/terraform.tfvars.example bootstrap/accounts/prod/terraform.tfvars
```

sh/bash/zsh:

```sh
cp bootstrap/accounts/prod/terraform.tfvars.example bootstrap/accounts/prod/terraform.tfvars
```

### Bootstrap Prod

```sh
terraform -chdir=bootstrap/accounts/prod init -backend=false
terraform -chdir=bootstrap/accounts/prod apply
terraform -chdir=bootstrap/accounts/prod output github_actions_role_arn
```

Then create the shared state bucket and bucket policy. Add the dev account principal and the GitHub role ARNs from the account bootstrap outputs to `trusted_state_access` before the first apply.

Each entry is scoped to one state key prefix. This lets the dev account access only `example-app/dev/<dev-account-id>/*`, while staging and prod can access only their own prefixes. Global and region-specific state keys live under those prefixes.

For cross-account dev access, the state bucket policy grants the resource-side permission only. The dev IAM user or role also needs identity-based S3 permissions for `s3:GetBucketLocation`, `s3:ListBucket`, `s3:GetObject`, `s3:PutObject`, and `s3:DeleteObject` on its allowed state prefix.

PowerShell:

```powershell
Copy-Item bootstrap/state/terraform.tfvars.example bootstrap/state/terraform.tfvars
```

sh/bash/zsh:

```sh
cp bootstrap/state/terraform.tfvars.example bootstrap/state/terraform.tfvars
```

### Bootstrap State

```sh
terraform -chdir=bootstrap/state init -backend=false
terraform -chdir=bootstrap/state apply
terraform -chdir=bootstrap/state output state_bucket_name
```

### Migrate Bootstrap State

After the bootstrap apply succeeds, migrate the bootstrap roots from local state into the same S3 state bucket. Otherwise the state bucket and GitHub Actions roles are still managed by local `terraform.tfstate` files, which are easy to lose and hard to share.

A normal `terraform init` in these roots should only happen after the state bucket exists and a generated `backend.tf` file is present. Use `terraform init -backend=false` only for the initial local bootstrap. After the state bucket exists, copy the backend examples and use `terraform init -migrate-state` to copy the local state into S3.

Create ignored backend files for the bootstrap roots by copying the committed examples. `backend.tf.example` contains the full S3 backend configuration for each bootstrap root. Use the state account profile for the backend, even when the Terraform provider in `terraform.tfvars` uses the staging or production admin profile. Backend credentials and provider credentials are separate.

PowerShell:

```powershell
Copy-Item bootstrap/state/backend.tf.example bootstrap/state/backend.tf
Copy-Item bootstrap/accounts/staging/backend.tf.example bootstrap/accounts/staging/backend.tf
Copy-Item bootstrap/accounts/prod/backend.tf.example bootstrap/accounts/prod/backend.tf
```

sh/bash/zsh:

```sh
cp bootstrap/state/backend.tf.example bootstrap/state/backend.tf
cp bootstrap/accounts/staging/backend.tf.example bootstrap/accounts/staging/backend.tf
cp bootstrap/accounts/prod/backend.tf.example bootstrap/accounts/prod/backend.tf
```

In the copied `backend.tf` files, replace `example-app`, `000000000000`, the bucket name, region, and profile with your real state account values.

Then migrate each local state file to S3.

```sh
terraform -chdir=bootstrap/state init -migrate-state
terraform -chdir=bootstrap/accounts/staging init -migrate-state
terraform -chdir=bootstrap/accounts/prod init -migrate-state
```

Answer `yes` when Terraform asks whether to copy the existing local state to the new backend. After migration, run a plan for each root and expect no changes:

```sh
terraform -chdir=bootstrap/state plan
terraform -chdir=bootstrap/accounts/staging plan
terraform -chdir=bootstrap/accounts/prod plan
```

The local `terraform.tfstate` files are no longer the source of truth after migration. Keep them only as temporary migration backups until the remote plans are clean, then delete the local copies. Future bootstrap changes should be applied from the same roots with the S3 backend initialized.

Finally, replace `000000000000` with the real state account ID in your local dev backend configs:

```text
envs/dev/global/backend.hcl
envs/dev/regional/backend.hcl
```

Environment staging and production backend blocks contain placeholder bucket, key, and region values so `terraform validate` works in CI. GitHub Actions override those placeholders at `terraform init`, so real state bucket names and account IDs do not need to be committed for those roots.

## Local Profiles

Local roots support a local-only `profile` variable in ignored `terraform.tfvars` files, so you do not need to export `AWS_PROFILE`.

PowerShell:

```powershell
Copy-Item envs/dev/global/terraform.tfvars.example envs/dev/global/terraform.tfvars
Copy-Item envs/dev/global/backend.hcl.example envs/dev/global/backend.hcl

Copy-Item envs/dev/regional/terraform.tfvars.example envs/dev/regional/terraform.tfvars
Copy-Item envs/dev/regional/backend.hcl.example envs/dev/regional/backend.hcl
```

sh/bash/zsh:

```sh
cp envs/dev/global/terraform.tfvars.example envs/dev/global/terraform.tfvars
cp envs/dev/global/backend.hcl.example envs/dev/global/backend.hcl

cp envs/dev/regional/terraform.tfvars.example envs/dev/regional/terraform.tfvars
cp envs/dev/regional/backend.hcl.example envs/dev/regional/backend.hcl
```

Example dev config:

```hcl
region         = "ap-southeast-2"
profile        = "dev"
app_name       = "example-app"
aws_account_id = "111111111111"
```

The S3 backend does not inherit the provider's `profile = "dev"`, so set `profile = "dev"` in each local backend config too:

```hcl
bucket       = "example-app-terraform-state-000000000000"
key          = "example-app/dev/111111111111/ap-southeast-2/terraform.tfstate"
region       = "ap-southeast-2"
profile      = "dev"
```

For local dev, use the dev account ID in the state key:

```hcl
key = "example-app/dev/111111111111/ap-southeast-2/terraform.tfstate"
```

The account ID keeps each developer's dev state separate while still using the same central state bucket. The region segment keeps each regional deployment in separate state. The global stack uses this key shape:

```hcl
key = "example-app/dev/111111111111/global/terraform.tfstate"
```

## Local Dev Deploy

Deploy the global stack first, then the regional stack.

```sh
terraform -chdir=envs/dev/global init -backend-config backend.hcl
terraform -chdir=envs/dev/global apply

terraform -chdir=envs/dev/regional init -backend-config backend.hcl
terraform -chdir=envs/dev/regional apply
```

## GitHub Environments

Create GitHub environments named `staging` and `production`.

> **Required for push-based promotion:** Add required reviewers to the `production` GitHub Environment. Because `.github/workflows/terraform-deploy.yml` uses `environment: production` for production jobs, this creates a manual approval gate between staging and production. Without environment protection, pushes to `main` can continue into production automatically.

Set these variables before the first GitHub deployment:

| Variable | Scope | Required | Notes |
| --- | --- | --- | --- |
| `AWS_ACCOUNT_ID` | `staging` and `production` environments | Yes | Target AWS account ID for that environment. |
| `AWS_ROLE_ARN` | `staging` and `production` environments | Yes | Role ARN from the matching bootstrap account output. |
| `TF_STATE_BUCKET` | Repository or both environments | Yes | Shared Terraform state bucket name from `bootstrap/state`. |
| `APP_NAME` | Repository | Recommended | Defaults to `example-app`; set before first deploy so state keys, role names, and tags match your project. |
| `AWS_REGION` | Repository | Optional | Single default regional deployment region. Defaults to `ap-southeast-2`. |
| `AWS_REGIONS_JSON` | Repository | Optional | JSON array of regional deployment regions. Overrides `AWS_REGION`. |
| `TF_GLOBAL_REGION` | Repository | Optional | Provider region for global/shared stacks. Falls back to `TF_STATE_REGION`, `AWS_REGION`, then `ap-southeast-2`. |
| `TF_STATE_REGION` | Repository | Optional | Region containing the S3 state bucket. Falls back to `AWS_REGION`, then `ap-southeast-2`. |

Use `AWS_REGIONS_JSON` for multi-region deployment, for example:

```json
["ap-southeast-2", "us-east-1"]
```

If `AWS_REGIONS_JSON` is unset, the deploy workflow uses `AWS_REGION`. If both are unset, it falls back to `ap-southeast-2`.

Use `TF_GLOBAL_REGION` when global/shared resources must be managed from a specific AWS provider region, such as `us-east-1` for some CloudFront-related resources. If unset, it falls back to `TF_STATE_REGION`, then `AWS_REGION`, then `ap-southeast-2`.

Use the role ARN output from the matching bootstrap account root. `AWS_ACCOUNT_ID` is passed to Terraform as `TF_VAR_aws_account_id`, and `TF_STATE_BUCKET` is passed to `terraform init` as backend config. `APP_NAME` defaults to `example-app` if unset; set it before the first deploy so state keys, role names, and tags match your project.

The bootstrap roots use Terraform AWS modules for the state S3 bucket and GitHub OIDC deployment roles. The account bootstrap roots attach AWS managed `AdministratorAccess` through the `policies` map in `bootstrap/modules/github-actions-role/main.tf`. This lets Terraform create, update, and destroy application infrastructure without changing IAM permissions for every new resource type. If you need least privilege, replace `AdministratorAccess` with a scoped policy containing only the actions and resources required by your Terraform stacks. Keep the Terraform state S3 permissions unless you replace them with equivalent state access, especially when the state bucket is in a separate AWS account.

Staging and production state keys are split by stack scope:

```text
example-app/staging/global/terraform.tfstate
example-app/staging/<region>/terraform.tfstate
example-app/prod/global/terraform.tfstate
example-app/prod/<region>/terraform.tfstate
```

Pushes to `main` deploy staging global first, then staging regional resources in a matrix. Production then waits on the `production` GitHub Environment approval gate before deploying global first, followed by regional resources in a matrix. After production succeeds, staging regional resources are destroyed, then staging global resources are destroyed for full-region runs.

Manual workflow runs can override the region to deploy only one regional stack. Global deploy still runs once because shared resources may be dependencies. Global destroy only runs for full environment destroys, not single-region destroys.

The deploy workflow passes backend config to `terraform init` at runtime, so state bucket names and account IDs do not need to be committed.

Pull request checks run in `.github/workflows/terraform-checks.yml`. They validate all bootstrap, global, and regional roots, then run staging plans for both global and regional stacks when the pull request branch is in this repository. Those staging plan jobs also post or update pull request comments with the plan output for review. Pull requests from forks run validation only, so AWS OIDC credentials are not exposed to untrusted fork workflows.

Production destroy is intentionally separated into `.github/workflows/terraform-destroy-prod.yml`. It only runs manually, requires typing `destroy production`, and uses the `production` GitHub Environment required-reviewer gate. It destroys regional stacks first and only destroys the production global stack when `region` is `all`.

Staging and production example values are committed without real account IDs:

```text
envs/staging/global/terraform.tfvars.example
envs/staging/regional/terraform.tfvars.example
envs/prod/global/terraform.tfvars.example
envs/prod/regional/terraform.tfvars.example
```

The state bucket can be the same bucket for all environments. If that bucket is in a separate AWS account, the bucket policy must trust the GitHub deployment roles that need to read/write Terraform state.
