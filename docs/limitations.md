# Limitations and next steps

[← README](../README.md)

## Assumptions

- **One dev environment.** A second one is another state key plus a tfvars file.
- **Author instance only.** A public instance is a next step.
- **Region `eu-west-1`**, instance `m7i-flex.large` (8 GB; Magnolia runs with a 4 GB heap).
- **No custom domain**, so CloudFront uses its default certificate.

## Known limitations

| Limitation | Impact | Next step |
|---|---|---|
| CloudFront → ALB is plain HTTP | Traffic inside AWS's network is not encrypted. | Custom domain + ACM on an HTTPS listener, or CloudFront VPC origins with an internal ALB. |
| Single EC2 instance in one AZ | If it fails, Magnolia is down until it is replaced. | A shared store first (next row), then an ASG. |
| Content on the instance's disk (embedded H2) | No point-in-time recovery; data is lost with the instance. | RDS PostgreSQL for the JCR, S3 for assets, backups. |
| First boot needs the internet | Provisioning depends on Magnolia's Nexus and the NAT. | Bake an AMI with Packer, or mirror the WAR to S3. |
| Origin-verify secret is in Terraform state | Anyone who can read state can bypass CloudFront. | State is private and encrypted; VPC origins remove the secret. |
| No WAF, alarms or log shipping | Operating blind. | WAF managed rules, CloudWatch logs and alarms. |
| Apply role is broader than this stack needs | IAM is fenced; other services are not. | A policy scoped from CloudTrail activity. |
| Bootstrap state is local | Losing it means re-importing a few resources. | Migrate it into the bucket it creates. |

## How I would keep moving forward

1. **Environments:** promote the same commit through `dev → staging → prod`, and add a nightly drift-detection plan.
2. **Immutable images:** a Packer-built AMI (or a container on ECS Fargate), so boots take seconds and need no internet.
3. **Stateful tier:** RDS and S3, after which instances are disposable and can scale out.
4. **Magnolia topology:** public instances behind CloudFront with real caching; the author instance behind the corporate IdP.
5. **Observability and security:** logs, alarms on ALB 5xx and unhealthy hosts, WAF, HTTPS to the origin.

## Cost

Roughly **$4–5/day** in `eu-west-1`: EC2 ≈ $2.4, NAT gateway ≈ $1.1, ALB ≈ $0.6, public IPv4 addresses ≈ $0.4. `terraform destroy` removes everything except the state bucket.
