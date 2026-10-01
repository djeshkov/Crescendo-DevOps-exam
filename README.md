# Crescendo DevOps Exam: Magnolia CMS on AWS

Terraform deploys Magnolia CMS Community Edition 6.4 on AWS: one EC2 instance in a private subnet, behind an Application Load Balancer and a CloudFront distribution. Nginx, Tomcat and Magnolia are installed on the instance automatically at first boot.

- **Magnolia URL:** `https://<distribution>.cloudfront.net/.magnolia/admincentral` (from the `magnolia_url` output)
- **Login:** `superuser`. The password is generated at deploy time and stored in SSM Parameter Store (see [Log in](#4-log-in)).

## Scope

Everything the exam asked for is here: the VPC with 2 public and 2 private subnets, IGW, NAT, one EC2 instance in a private subnet, the ALB, CloudFront, Nginx → Tomcat → Magnolia provisioned by Terraform, `fmt`/`validate`/`plan` on PRs, and this README.

A few things go beyond the brief. Each is small and closes a real gap:

- **Apply on merge, behind a manual approval.** It answers "how would you keep moving forward", and it means nobody needs admin keys on a laptop.
- **Unattended Magnolia setup.** Magnolia 6.4 otherwise asks the first visitor of a public URL to set the admin password.
- **The ALB is reachable only through this CloudFront distribution**, not from the internet.

## Architecture

![Architecture: viewers reach CloudFront, which forwards to the ALB in the public subnets and on to Nginx, Tomcat and Magnolia on a private EC2 instance; the instance reaches the internet only through the NAT gateway, and operators connect through SSM Session Manager](docs/architecture.png)

<sub>Generated from [`docs/architecture.py`](docs/architecture.py) with [diagrams](https://diagrams.mingrammer.com/). To regenerate: `pip install diagrams` (needs Graphviz), then `python docs/architecture.py && python docs/cicd.py`. Solid blue is the request path, dashed grey is outbound traffic from the instance, dotted purple is operator access. The CI/CD pipeline has its own diagram [below](#cicd-github-actions).</sub>

### How a request flows

1. **CloudFront** terminates TLS with the default `*.cloudfront.net` certificate and redirects HTTP to HTTPS. Magnolia pages are dynamic and AdminCentral needs a login, so the default behaviour does not cache anything. Only Magnolia's static UI assets (`/.resources/*`, `/VAADIN/*`) are cached. Every request to the origin gets a secret `X-Origin-Verify` header.
2. **ALB** accepts connections only from CloudFront's origin-facing IP ranges (AWS-managed prefix list in the security group). Those IPs are shared by every CloudFront customer, so the listener also returns `403` unless the secret header matches. The result: the ALB is only reachable through *this* distribution.
3. **Nginx** reverse-proxies to Tomcat. It passes the viewer's scheme from `CloudFront-Forwarded-Proto`, so Magnolia generates `https://` URLs for the CloudFront hostname. It also supports WebSocket upgrades (Vaadin push in AdminCentral) and allows 100 MB uploads for the DAM.
4. **Tomcat 10.1** listens on `127.0.0.1` only. A `RemoteIpValve` trusts Nginx's `X-Forwarded-*` headers.
5. **Magnolia** runs as the root context. The ALB health check calls Magnolia's own readiness probe, `/.rest/health/ready` (JCR datastore and superuser setup). A healthy target therefore means the whole Nginx → Tomcat → Magnolia chain works, not just that Nginx is up.

### Design decisions

| Decision | Why |
|---|---|
| Four small modules: `network`, `app`, `alb`, `cdn` | Each has one job and a narrow interface. Swapping EC2 for an ASG or ECS later only touches `app`. |
| Amazon Linux 2023 packages (`tomcat10`, Corretto 17, `nginx`) | Distro packages get security fixes through `dnf`. Magnolia 6.4 is Jakarta EE, so it needs Tomcat 10.1 and Java 17. |
| Magnolia WAR pinned by version and SHA-256 | Provisioning is reproducible and aborts on a tampered or changed download. |
| Magnolia config in a profile directory (`MAGNOLIA_PROFILE=aws`) | Vendor files stay untouched: the whole diff to stock Magnolia is one properties file. Content lives in `/var/lib/magnolia`, outside the webapp, so an upgrade means dropping in a new WAR. |
| Unattended install (`magnolia.update.auto=true`) and superuser password from a file | By default Magnolia 6.4 shows a "set superuser password" form to the first visitor. On a public URL, that visitor could be anyone. |
| Password: ephemeral `random_password` → SSM SecureString (`value_wo`) | The password is never written to Terraform state or plans. The instance reads it through its IAM role. |
| No SSH, no bastion; SSM Session Manager | No inbound ports besides ALB → Nginx and no keys to manage. Every session is authenticated with IAM. |
| IMDSv2 required, encrypted gp3 root volume | Baseline EC2 hardening. |
| `user_data_replace_on_change = true` | Provisioning runs at first boot only. A changed script without replacement would show a change in the plan that never reaches the server. |
| AMI resolved once, then `ignore_changes` | A new Amazon Linux release must not silently replace the server. Moving to a new AMI is a deliberate `-replace`. |
| One NAT gateway (`single_nat_gateway = true`) | Halves the cost for a dev environment. Set it to `false` for one NAT per AZ; the route tables are already per AZ. |
| S3 gateway endpoint | Free. Amazon Linux repos are served from S3, so `dnf` traffic skips the NAT. |
| Remote state in S3 with native locking (`use_lockfile`) | No DynamoDB table needed (Terraform ≥ 1.10). |
| CI authenticates with GitHub OIDC; separate plan/apply roles | No long-lived AWS keys in GitHub. Plan is read-only; apply needs a manual approval and is boxed in by a permissions boundary. See [Security model](#security-model). |

## Repository layout

```
.
├── bootstrap/                 # one-time per account: state bucket, GitHub OIDC, CI roles, boundary
├── terraform/                 # the Magnolia stack
│   ├── main.tf                # wires the modules together
│   ├── modules/
│   │   ├── network/           # VPC, 2 public + 2 private subnets, IGW, NAT, routes, S3 endpoint
│   │   ├── app/               # EC2, IAM/SSM, security group, superuser password
│   │   │   └── templates/user-data.sh.tftpl   # Nginx + Tomcat + Magnolia provisioning
│   │   ├── alb/               # ALB, target group, CloudFront-only access
│   │   └── cdn/               # CloudFront distribution
│   ├── backend.hcl.example
│   └── terraform.tfvars.example
├── docs/                         # diagrams as code: architecture.py, cicd.py → *.png
├── scripts/plan-fingerprint.sh       # hash of planned changes: apply only what was approved
├── .github/workflows/terraform.yml   # PR: fmt → validate + tflint → plan · main: … → approve → apply
└── .terraform-version          # pinned Terraform version (tenv / setup-terraform)
```

## How to run it

Day-to-day changes go through the pipeline: **PR → plan → merge → approve → apply**. The only manual step is the one-time bootstrap, which creates the roles the pipeline itself uses.

### Prerequisites

- Terraform ≥ 1.11 (pinned in `.terraform-version`)
- AWS CLI v2 and admin credentials for the target account, needed for the bootstrap only
- The [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) for the AWS CLI (optional; for shell access)

### 1. Bootstrap (once per account, by a human)

```bash
cd bootstrap
terraform init
terraform apply        # for another repo: -var github_oidc_subject_prefix=$(gh api repos/<owner>/<repo>/actions/oidc/customization/sub --jq .sub_claim_prefix)
terraform output
```

This creates the state bucket, the GitHub OIDC provider, the two CI roles and the permissions boundary. The pipeline cannot modify any of them (see [CI/CD](#cicd-github-actions)).

### 2. Configure GitHub (once)

| Where | Name | Value |
|---|---|---|
| Repository variable | `AWS_PLAN_ROLE_ARN` | `github_plan_role_arn` output |
| Repository variable | `AWS_APPLY_ROLE_ARN` | `github_apply_role_arn` output |
| Repository variable | `TF_STATE_BUCKET` | `state_bucket` output |
| Repository variable | `AWS_REGION` | optional, defaults to `eu-west-1` |
| Environment | `aws-dev` | required reviewers; deployment branches: `main` only |
| Branch protection | `main` | PR required; required checks: `fmt`, `validate (terraform)`, `validate (bootstrap)`, `plan` |

These are variables, not secrets: with OIDC there is nothing secret to store in GitHub.

### 3. Deploy

Open a PR. The plan appears as a PR comment. Merge the PR, review the plan in the run summary, and approve the `aws-dev` deployment. The apply takes about 5 minutes; CloudFront is the slow part. Magnolia then installs itself in the background in another 3–5 minutes. The URL is in the run summary.

<details><summary>Deploying from a workstation instead (break-glass)</summary>

```bash
cd terraform
cp backend.hcl.example backend.hcl        # set bucket = <state_bucket output>
terraform init -backend-config=backend.hcl
terraform apply
```

</details>

### 4. Log in

Open `terraform output magnolia_url`. The user is `superuser`; get the password with:

```bash
$(terraform output -raw superuser_password_command)
```

### 5. Shell access and logs

```bash
aws ssm start-session --target $(terraform output -raw instance_id)
sudo tail -f /var/log/magnolia-bootstrap.log          # provisioning
sudo tail -f /var/lib/magnolia/logs/magnolia-debug.log # Magnolia
sudo journalctl -u tomcat10 -u nginx
```

### Tear down

```bash
cd terraform && terraform init -backend-config=backend.hcl && terraform destroy
```

The apply role cannot delete the state bucket, and `bootstrap/` has `prevent_destroy` on it. Removing the foundation is always a deliberate, manual step.

## CI/CD: GitHub Actions

`.github/workflows/terraform.yml`:

![CI/CD: a pull request runs fmt, validate and plan and posts the plan as a comment; a merge to main runs plan, waits for approval in the aws-dev environment, re-plans, and applies only if the plan fingerprint is unchanged. Plan jobs use a read-only role and apply uses a fenced role, both through GitHub OIDC](docs/cicd.png)

<sub>Generated from [`docs/cicd.py`](docs/cicd.py) with the same shared style as the architecture diagram (`docs/_style.py`).</sub>

| Job | Runs on | AWS access |
|---|---|---|
| `fmt` | PR, main | none |
| `validate` | PR, main | none. `init -backend=false -lockfile=readonly`, `validate` and `tflint` (AWS ruleset) for both stacks |
| `plan` | PR, main | plan role (read-only). Posted as a sticky PR comment and in the job summary |
| `apply` | main, only when the plan has changes | apply role, after approval in the `aws-dev` environment |

### Security model

- **No long-lived credentials.** GitHub OIDC tokens are exchanged for 1-hour AWS sessions. Each role trusts one exact token subject:
  - plan: `<prefix>:pull_request` and `<prefix>:ref:refs/heads/main`
  - apply: `<prefix>:environment:aws-dev`

  The prefix is GitHub's immutable subject, `repo:djeshkov@10827228/Crescendo-DevOps-exam@1398084996`. It embeds the owner and repository IDs, so a renamed or re-created repository with the same name cannot assume the roles. Forks receive no OIDC token at all.
- **The plan role is read-only** (`ReadOnlyAccess`); its one write is the state lock file. Anyone who can open a PR can change the workflow and run code with this role, so it must never be able to change anything. For the same reason, secrets stay out of state where possible: the Magnolia password is ephemeral and write-only.
- **The apply role is `PowerUserAccess` plus fenced IAM:**
  - It can create IAM roles and instance profiles only under the `magnolia-*` prefix.
  - It can create a role or grant it permissions only if the role carries the `magnolia-workload-boundary` permissions boundary, and it cannot remove that boundary.
  - It can pass roles to EC2 only.

  So even if a malicious change attaches `AdministratorAccess` to a workload role, the role's effective rights stay inside the boundary: SSM agent, its own parameters, logs. The CI roles are named `github-magnolia-*`, outside that prefix, so the pipeline can never edit the roles it runs as. It also cannot delete or reconfigure the state bucket.
- **Apply executes exactly what was approved.** The plan file is not passed between jobs: it contains sensitive values in clear text, and artifacts of a public repository are downloadable by anyone. Instead, `scripts/plan-fingerprint.sh` hashes the planned changes. The apply job re-plans and refuses to apply if the hash differs from the approved one.
- **Supply chain.** Actions are pinned to commit SHAs. Provider hashes are pinned in `.terraform.lock.hcl`, and CI refuses to deviate (`-lockfile=readonly`). Dependabot proposes updates for both.
- **Least-privilege tokens.** `permissions:` are set per job. Only `plan` can comment on PRs; only `plan` and `apply` can request OIDC tokens.
- **No races.** PR runs cancel superseded runs; runs on `main` queue and never cancel. Terraform's S3 lock is the second line of defence.

## Assumptions

- **A single dev environment is enough to demonstrate the approach.** Everything is parameterised by `project`/`environment`. A second environment is another state key plus a tfvars file.
- **Author instance only.** It is Magnolia's editing instance and what a content team logs into. A public instance and publishing between the two are listed under next steps.
- **Region `eu-west-1`.** The instance type `m7i-flex.large` (2 vCPU, 8 GB) is free-tier eligible on new accounts. Magnolia runs with a 4 GB heap; the JVM uses about 2.6 GB of RAM at idle.
- **No custom domain**, so CloudFront uses its default certificate. See the limitations below.
- **Every apply is approved by a human.** The exam asks for plan on PR; this repository also applies on merge, behind a manual approval gate.

## Known limitations

| Limitation | Impact | Next step |
|---|---|---|
| CloudFront → ALB is plain HTTP | The traffic crosses AWS's network but is not encrypted in transit. The header secret travels in clear text. | Custom domain + ACM certificate on an HTTPS listener, or CloudFront **VPC origins** with an *internal* ALB, so there is no public ALB at all. |
| Single EC2 instance, single AZ for compute | If the instance or its AZ fails, Magnolia is down until it is replaced. | Magnolia keeps state on local disk, so HA first needs a shared store (below). Then an ASG plus an AMI baked with Packer. |
| JCR repository on the root EBS volume (embedded H2) | No point-in-time recovery; the data goes away with the instance. | RDS PostgreSQL for the JCR, a separate EBS data volume, AWS Backup / DLM snapshots. |
| First boot needs the internet | Provisioning depends on the Magnolia Nexus and the NAT being up. | Bake an AMI with Packer, or mirror the WAR to a private S3 bucket. |
| Superuser password is only read on first install | Rotating it in SSM does not change Magnolia. | Change it in AdminCentral, or reprovision the instance. |
| The origin-verify secret is in Terraform state | Anyone who can read state can bypass CloudFront. | State is encrypted and private. Rotate by tainting `random_password.origin_verify`; better, move to VPC origins. |
| `/.rest/health` is publicly reachable through CloudFront | It exposes only an UP/DOWN status. | Block the path with a CloudFront behaviour or a WAF rule. |
| No WAF, no alarms, no log shipping | Operating blind. | See below. |
| Bootstrap state is local | Losing it means re-importing a handful of resources. | Migrate it into the bucket it creates after the first apply. |
| Apply role is PowerUser (all non-IAM services) | Broader than this stack needs. IAM, the usual escalation path, is fenced by the boundary. | Service-scoped policy generated from CloudTrail activity (IAM Access Analyzer policy generation). |

## How I would keep moving forward

1. **Delivery:** promote the same commit through `dev → staging → prod`, one environment and state key each, with prod approvals restricted to a release team. Add a nightly drift-detection plan that alerts on changes made outside Terraform.
2. **Immutable images:** Packer builds a Magnolia AMI (or a container for ECS Fargate) in CI. `user_data` shrinks to configuration, and boots take seconds instead of minutes.
3. **Stateful tier:** RDS PostgreSQL for the JCR repositories and S3 for the DAM binary store. After that, instances are disposable and can scale out.
4. **Magnolia topology:** a separate public instance (or a cluster of them) behind CloudFront with real caching, and the author instance on a restricted hostname or behind the corporate IdP.
5. **Security:** custom domain + ACM, AWS WAF with managed rules on CloudFront, CloudFront → internal ALB via VPC origins, GuardDuty, and ALB/CloudFront access logs to S3.
6. **Observability:** CloudWatch agent for Magnolia/Tomcat/Nginx logs and JVM metrics; alarms on ALB 5xx, unhealthy hosts and instance status; an uptime check on the CloudFront URL.
7. **Cost:** schedule the dev environment down outside working hours, or use a NAT instance for dev.

## Cost

Roughly **$4–5/day** in `eu-west-1` for the dev setup: EC2 `m7i-flex.large` ≈ $2.4, NAT gateway ≈ $1.1, ALB ≈ $0.6, public IPv4 addresses ≈ $0.4. New accounts pay this from free-tier credits. CloudFront and S3 costs are negligible at this traffic. `terraform destroy` removes everything except the state bucket.
