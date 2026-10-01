output "state_bucket" {
  description = "S3 bucket for the main stack's state -> GitHub variable TF_STATE_BUCKET and backend.hcl."
  value       = aws_s3_bucket.state.bucket
}

output "github_plan_role_arn" {
  description = "IAM role for CI plans -> GitHub variable AWS_PLAN_ROLE_ARN."
  value       = aws_iam_role.github_plan.arn
}

output "github_apply_role_arn" {
  description = "IAM role for CI applies -> GitHub variable AWS_APPLY_ROLE_ARN."
  value       = aws_iam_role.github_apply.arn
}

output "workload_permissions_boundary_arn" {
  description = "Permissions boundary every role of the main stack must carry."
  value       = aws_iam_policy.workload_boundary.arn
}
