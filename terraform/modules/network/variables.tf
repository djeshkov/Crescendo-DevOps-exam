variable "name" {
  description = "Name prefix for all network resources."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC. Must be a /16 so the /24 subnet layout fits."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && endswith(var.vpc_cidr, "/16")
    error_message = "vpc_cidr must be a valid /16 CIDR block."
  }
}

variable "az_count" {
  description = "Number of availability zones to spread public and private subnets across."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2
    error_message = "At least two AZs are required (the ALB needs subnets in two AZs)."
  }
}

variable "single_nat_gateway" {
  description = "Share one NAT gateway between all private subnets (cheaper) instead of one per AZ (highly available)."
  type        = bool
  default     = true
}
