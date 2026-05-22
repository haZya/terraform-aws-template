# Terraform AWS template for multi-account and multi-regional deployments

This repo uses separate Terraform root modules per environment, split into global/shared and regional stacks.

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

## Stack Boundaries

Put resources that are deployed once per environment in `global/`. Examples: IAM, Route 53 zones, CloudFront, Global Accelerator, shared KMS keys, or anything that should not be recreated once per region.

Put resources that are deployed once per region in `regional/`.

Global and regional stacks use separate state files. Deploy global first when regional resources depend on shared resources. Destroy regional first, then global.

## Bootstrap Order

All bootstrap roots include an S3 backend block with placeholder values, but the first bootstrap run must initialize with `-backend=false` because the remote state bucket does not exist yet. That first run uses local state. Use a fixed state account ID up front so the future state bucket name is known before the bucket exists.

With the default convention, the bucket name is:

```text
<app_name>-terraform-state-<state-account-id>
```

For example:

```text
example-app-terraform-state-000000000000
```

Create the GitHub OIDC deployment roles first. IAM policies can reference the future state bucket ARN before the bucket exists.

PowerShell:

```powershell
Copy-Item bootstrap/accounts/staging/terraform.tfvars.example bootstrap/accounts/staging/terraform.tfvars
terraform -chdir=bootstrap/accounts/staging init -backend=false
terraform -chdir=bootstrap/accounts/staging apply
terraform -chdir=bootstrap/accounts/staging output github_actions_role_arn
```

sh/bash/zsh:

```sh
cp bootstrap/accounts/staging/terraform.tfvars.example bootstrap/accounts/staging/terraform.tfvars
terraform -chdir=bootstrap/accounts/staging init -backend=false
terraform -chdir=bootstrap/accounts/staging apply
terraform -chdir=bootstrap/accounts/staging output github_actions_role_arn
```

PowerShell:

```powershell
Copy-Item bootstrap/accounts/prod/terraform.tfvars.example bootstrap/accounts/prod/terraform.tfvars
terraform -chdir=bootstrap/accounts/prod init -backend=false
terraform -chdir=bootstrap/accounts/prod apply
terraform -chdir=bootstrap/accounts/prod output github_actions_role_arn
```

sh/bash/zsh:

```sh
cp bootstrap/accounts/prod/terraform.tfvars.example bootstrap/accounts/prod/terraform.tfvars
terraform -chdir=bootstrap/accounts/prod init -backend=false
terraform -chdir=bootstrap/accounts/prod apply
terraform -chdir=bootstrap/accounts/prod output github_actions_role_arn
```

Then create the shared state bucket and bucket policy. Add the dev account principal and the GitHub role ARNs from the account bootstrap outputs to `trusted_state_access` before the first apply.

Each entry is scoped to one state key prefix. This lets the dev account access only `example-app/dev/<dev-account-id>/*`, while staging and prod can access only their own prefixes. Global and region-specific state keys live under those prefixes.

PowerShell:

```powershell
Copy-Item bootstrap/state/terraform.tfvars.example bootstrap/state/terraform.tfvars
terraform -chdir=bootstrap/state init -backend=false
terraform -chdir=bootstrap/state apply
terraform -chdir=bootstrap/state output state_bucket_name
```

sh/bash/zsh:

```sh
cp bootstrap/state/terraform.tfvars.example bootstrap/state/terraform.tfvars
terraform -chdir=bootstrap/state init -backend=false
terraform -chdir=bootstrap/state apply
terraform -chdir=bootstrap/state output state_bucket_name
```

### Migrate Bootstrap State

After the bootstrap apply succeeds, migrate the bootstrap roots from local state into the same S3 state bucket. Otherwise the state bucket and GitHub Actions roles are still managed by local `terraform.tfstate` files, which are easy to lose and hard to share.

A normal `terraform init` in these roots tries to configure the placeholder S3 backend, so use `terraform init -backend=false` only for the initial local bootstrap. After the state bucket exists, use `terraform init -migrate-state -backend-config backend.hcl` to override the placeholders and copy the local state into S3.

Create ignored backend config files for the bootstrap roots. Use the state account profile for the backend, even when the Terraform provider in `terraform.tfvars` uses the staging or production admin profile. Backend credentials and provider credentials are separate.

`bootstrap/state/backend.hcl`:

```hcl
bucket       = "example-app-terraform-state-000000000000"
key          = "example-app/bootstrap/state/terraform.tfstate"
region       = "ap-southeast-2"
profile      = "state-account"
encrypt      = true
use_lockfile = true
```

`bootstrap/accounts/staging/backend.hcl`:

```hcl
bucket       = "example-app-terraform-state-000000000000"
key          = "example-app/bootstrap/accounts/staging/terraform.tfstate"
region       = "ap-southeast-2"
profile      = "state-account"
encrypt      = true
use_lockfile = true
```

`bootstrap/accounts/prod/backend.hcl`:

```hcl
bucket       = "example-app-terraform-state-000000000000"
key          = "example-app/bootstrap/accounts/prod/terraform.tfstate"
region       = "ap-southeast-2"
profile      = "state-account"
encrypt      = true
use_lockfile = true
```

Replace `example-app`, `000000000000`, the bucket name, region, and profile with your real state account values.

Then migrate each local state file to S3.

PowerShell:

```powershell
terraform -chdir=bootstrap/state init -migrate-state -backend-config backend.hcl
terraform -chdir=bootstrap/accounts/staging init -migrate-state -backend-config backend.hcl
terraform -chdir=bootstrap/accounts/prod init -migrate-state -backend-config backend.hcl
```

sh/bash/zsh:

```sh
terraform -chdir=bootstrap/state init -migrate-state -backend-config backend.hcl
terraform -chdir=bootstrap/accounts/staging init -migrate-state -backend-config backend.hcl
terraform -chdir=bootstrap/accounts/prod init -migrate-state -backend-config backend.hcl
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

Staging and production backend files contain placeholder values only. GitHub Actions overrides them at `terraform init`, so state bucket names and account IDs do not need to be committed.

## Local Profiles

Local roots support a local-only `profile` variable in ignored `terraform.tfvars` files, so you do not need to export `AWS_PROFILE`.

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
encrypt      = true
use_lockfile = true
```

## Local Dev

Deploy the global stack first, then the regional stack.

PowerShell:

```powershell
Copy-Item envs/dev/global/terraform.tfvars.example envs/dev/global/terraform.tfvars
Copy-Item envs/dev/global/backend.hcl.example envs/dev/global/backend.hcl
terraform -chdir=envs/dev/global init -backend-config backend.hcl
terraform -chdir=envs/dev/global apply

Copy-Item envs/dev/regional/terraform.tfvars.example envs/dev/regional/terraform.tfvars
Copy-Item envs/dev/regional/backend.hcl.example envs/dev/regional/backend.hcl
terraform -chdir=envs/dev/regional init -backend-config backend.hcl
terraform -chdir=envs/dev/regional apply
```

sh/bash/zsh:

```sh
cp envs/dev/global/terraform.tfvars.example envs/dev/global/terraform.tfvars
cp envs/dev/global/backend.hcl.example envs/dev/global/backend.hcl
terraform -chdir=envs/dev/global init -backend-config backend.hcl
terraform -chdir=envs/dev/global apply

cp envs/dev/regional/terraform.tfvars.example envs/dev/regional/terraform.tfvars
cp envs/dev/regional/backend.hcl.example envs/dev/regional/backend.hcl
terraform -chdir=envs/dev/regional init -backend-config backend.hcl
terraform -chdir=envs/dev/regional apply
```

For local dev, use the dev account ID in the state key:

```hcl
key = "example-app/dev/111111111111/ap-southeast-2/terraform.tfstate"
```

The account ID keeps each developer's dev state separate while still using the same central state bucket. The region segment keeps each regional deployment in separate state. The global stack uses this key shape:

```hcl
key = "example-app/dev/111111111111/global/terraform.tfstate"
```

## GitHub Environments

Create GitHub environments named `staging` and `production`.

> **Recommended:** Add required reviewers to the `production` GitHub Environment. Because `.github/workflows/terraform-deploy.yml` uses `environment: production` for production jobs, this creates a manual approval gate between the staging deployment and production promotion.

Set these GitHub Environment variables on `staging` and `production`:

```text
AWS_ACCOUNT_ID
AWS_ROLE_ARN
```

Set these repository variables when they are shared across environments:

```text
AWS_REGIONS_JSON
AWS_REGION
APP_NAME
TF_GLOBAL_REGION
TF_STATE_BUCKET
TF_STATE_REGION
```

Use `AWS_REGIONS_JSON` for multi-region deployment, for example:

```json
["ap-southeast-2", "us-east-1"]
```

If `AWS_REGIONS_JSON` is unset, the deploy workflow uses `AWS_REGION`. If both are unset, it falls back to `ap-southeast-2`.

Use `TF_GLOBAL_REGION` when global/shared resources must be managed from a specific AWS provider region, such as `us-east-1` for some CloudFront-related resources. If unset, it falls back to `TF_STATE_REGION`, then `AWS_REGION`, then `ap-southeast-2`.

Use the role ARN output from the matching bootstrap account root. `AWS_ACCOUNT_ID` is passed to Terraform as `TF_VAR_aws_account_id`, and `TF_STATE_BUCKET` is passed to `terraform init` as backend config. `APP_NAME` defaults to `example-app` if unset; set it before the first deploy so state keys, role names, and tags match your project.

The bootstrap account roots attach AWS managed `AdministratorAccess` to the GitHub Actions deployment roles. This lets Terraform create, update, and destroy application infrastructure without changing IAM permissions for every new resource type. If you need least privilege, replace the `aws_iam_role_policy_attachment.github_actions_deployment` attachment in `bootstrap/modules/github-actions-role/main.tf` with a scoped policy containing only the actions and resources required by your Terraform stacks. Keep the Terraform state S3 permissions unless you replace them with equivalent state access, especially when the state bucket is in a separate AWS account.

Staging and production state keys are split by stack scope:

```text
example-app/staging/global/terraform.tfstate
example-app/staging/<region>/terraform.tfstate
example-app/prod/global/terraform.tfstate
example-app/prod/<region>/terraform.tfstate
```

Pushes to `main` deploy staging global first, then staging regional resources in a matrix. Production then deploys global first, followed by regional resources in a matrix. After production succeeds, staging regional resources are destroyed, then staging global resources are destroyed for full-region runs.

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
