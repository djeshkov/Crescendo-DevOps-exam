variable "project" {
  description = "Project name, used in the state bucket and role names."
  type        = string
  default     = "magnolia"
}

variable "aws_region" {
  description = "Region of the state bucket."
  type        = string
  default     = "eu-west-1"
}

variable "github_oidc_subject_prefix" {
  description = "OIDC `sub` prefix of the GitHub repository allowed to assume the CI roles. Get it with: gh api repos/<owner>/<repo>/actions/oidc/customization/sub --jq .sub_claim_prefix"
  type        = string
  default     = "repo:djeshkov@10827228/Crescendo-DevOps-exam@1398084996"

  validation {
    condition     = startswith(var.github_oidc_subject_prefix, "repo:")
    error_message = "github_oidc_subject_prefix must start with \"repo:\"."
  }
}

variable "github_apply_environment" {
  description = "GitHub Environment (required reviewers, main only) whose jobs may assume the apply role."
  type        = string
  default     = "aws-dev"
}
