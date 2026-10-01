# Running it

[← README](../README.md)

Day-to-day changes go through the pipeline: **PR → plan → merge → approve → apply**. Only the bootstrap is manual.

## Prerequisites

- Terraform ≥ 1.11 (pinned in `.terraform-version`)
- AWS CLI v2 with admin credentials for the target account (bootstrap only)
- Optional: the [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) for shell access

## 1. Bootstrap (once per account)

```bash
cd bootstrap
terraform init
terraform apply        # for another repo: -var github_oidc_subject_prefix=$(gh api repos/<owner>/<repo>/actions/oidc/customization/sub --jq .sub_claim_prefix)
terraform output
```

This creates the state bucket, the GitHub OIDC provider, the two CI roles and the permissions boundary.

## 2. Configure GitHub (once)

| Where | Name | Value |
|---|---|---|
| Repository variable | `AWS_PLAN_ROLE_ARN` | `github_plan_role_arn` output |
| Repository variable | `AWS_APPLY_ROLE_ARN` | `github_apply_role_arn` output |
| Repository variable | `TF_STATE_BUCKET` | `state_bucket` output |
| Repository variable | `AWS_REGION` | optional, defaults to `eu-west-1` |
| Environment | `aws-dev` | required reviewers; deployment branches: `main` only |
| Branch protection | `main` | PR required; required checks: `fmt`, `validate (terraform)`, `validate (bootstrap)`, `plan` |

No secrets are required: with OIDC there is nothing secret to store in GitHub.

## 3. Deploy

Open a PR; the plan appears as a comment. Merge it, review the plan in the run summary, and approve the `aws-dev` deployment. The apply takes about 5 minutes, and Magnolia then installs itself in another 3–5.

<details><summary>Deploying from a workstation instead (break-glass)</summary>

```bash
cd terraform
cp backend.hcl.example backend.hcl        # set bucket = <state_bucket output>
terraform init -backend-config=backend.hcl
terraform apply
```

</details>

## 4. Log in

Open `terraform output magnolia_url`. The user is `superuser`; get the password with:

```bash
$(terraform output -raw superuser_password_command)
```

## 5. Shell access and logs

```bash
aws ssm start-session --target $(terraform output -raw instance_id)
sudo tail -f /var/log/magnolia-bootstrap.log           # provisioning
sudo tail -f /var/lib/magnolia/logs/magnolia-debug.log # Magnolia
```

## Tear down

```bash
cd terraform && terraform init -backend-config=backend.hcl && terraform destroy
```

The state bucket stays: `bootstrap/` protects it with `prevent_destroy`.
