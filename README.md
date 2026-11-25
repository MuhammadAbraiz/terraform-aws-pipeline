# terraform-aws-pipeline

A Terraform pipeline for AWS where **pull requests can plan, but only an approved job on `main` can apply**.

```mermaid
flowchart LR
  subgraph PR["Pull request (pr.yml)"]
    A[fmt, validate,<br/>Checkov on code] --> B[plan role<br/>read-only] --> C[Checkov on plan] --> D[PR comment<br/>summary only]
  end
  subgraph MAIN["Merge to main (deploy.yml)"]
    E[plan role] --> F[Checkov on plan<br/>blocking] --> G[plan + SHA-256<br/>to private S3] --> H{{production<br/>approval}} --> I[apply role<br/>applies that plan] --> J[S3 + CloudFront]
  end
  B -. state + .tflock .-> S[(State bucket<br/>no DynamoDB)]
  I -. state + .tflock .-> S
```

## What's in here

| Path | What it is |
| --- | --- |
| `bootstrap/` | Applied once from your machine: state bucket, plan role, apply role |
| `infra/` | The workload: a private S3 bucket behind CloudFront with Origin Access Control |
| `site/` | The page that gets deployed |
| `.github/workflows/pr.yml` | Plan and scan on every pull request, sticky summary comment |
| `.github/workflows/deploy.yml` | Plan, scan, store the plan, wait for approval, apply that exact plan |
| `scripts/plan-summary.sh` | Turns the plan and Checkov JSON into a short, sanitized summary |

## Security model

- **Two OIDC roles, exact `sub` values.** The plan role trusts `pull_request` and `ref:refs/heads/main`. The apply role trusts only `environment:production`, and also requires `ref = refs/heads/main`. This repo was created after 15 July 2026, so the `sub` uses GitHub's immutable `owner@id/repo@id` format.
- **Least privilege.** The plan role reads state, writes only the `.tflock` file, and can upload plans but not read them. The apply role can read plans but not write them, and can only change CloudFront distributions tagged `Project=tfpipe`.
- **The applied plan is the reviewed plan.** The main-branch plan is scanned by Checkov (blocking), stored in the private state bucket with its SHA-256, and the apply job verifies the hash and refuses plans older than 24 hours.
- **Nothing sensitive in public places.** Raw plan and apply output never reach the logs. Saved plans never become GitHub artifacts: on a public repo anyone signed in could download them.
- **Native S3 locking.** `use_lockfile = true`, no DynamoDB table.

Threat model: this is a solo-maintainer repo. Anyone who can push a branch is trusted to read production state through a PR plan, and the single approver can approve their own deployment. Teams should run PR plans against a sandbox account and require a second reviewer.

## Setup

Requirements: Terraform 1.17, AWS CLI, admin credentials for the one-time bootstrap.

1. Get the repo's numeric IDs: `curl -s https://api.github.com/repos/OWNER/REPO | jq '{owner_id: .owner.id, repo_id: .id}'`
2. Bootstrap:
   ```bash
   cd bootstrap
   terraform init
   terraform apply -var="github_repo_id=<repo id>"
   ```
   Set `create_oidc_provider=true` if the account has no GitHub OIDC provider yet.
3. In the repo settings:
   - Secrets: `PLAN_ROLE_ARN`, `TF_STATE_BUCKET`, `AWS_ACCOUNT_ID`
   - Environment `production`: required reviewer, deployment branches limited to `main`, environment secret `APPLY_ROLE_ARN`
   - Ruleset on `main`: require a pull request and the status checks, block force pushes and deletion
4. Open a pull request.

## Teardown

```bash
cd infra
terraform init -backend-config="bucket=<state bucket>"
terraform destroy
cd ../bootstrap
terraform destroy -var="github_repo_id=<repo id>"
```

The state bucket is versioned, so empty all object versions before the last destroy.

## Article

Written up on AWS Builder Center (link coming).
