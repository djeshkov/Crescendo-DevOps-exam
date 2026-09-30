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

variable "github_repository" {
  description = "GitHub repository (owner/name) allowed to assume the plan role."
  type        = string
  default     = "djeshkov/Crescendo-DevOps-exam"
}

variable "github_apply_environment" {
  description = "GitHub Environment (required reviewers, main only) whose jobs may assume the apply role."
  type        = string
  default     = "aws-dev"
}
