variable "name" {
  description = "Name prefix for all resources."
  type        = string

  validation {
    condition     = length(var.name) <= 23
    error_message = "name must be at most 23 characters so '<name>-magnolia' fits the 32-character target group limit."
  }
}

variable "vpc_id" {
  description = "VPC of the ALB."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR; the ALB may only send traffic to targets inside it."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets (at least two AZs) for the ALB."
  type        = list(string)
}

variable "target_instance_id" {
  description = "EC2 instance registered in the target group."
  type        = string
}

variable "health_check_path" {
  description = "Target group health check path; must return 200 only when Magnolia is ready."
  type        = string
  default     = "/.rest/health/ready"
}

variable "origin_verify_header_name" {
  description = "Header CloudFront adds to every origin request; requests without it get 403."
  type        = string
}

variable "origin_verify_header_value" {
  description = "Secret value of the origin verification header."
  type        = string
  sensitive   = true
}
