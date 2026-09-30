variable "name" {
  description = "Name prefix for all resources."
  type        = string
}

variable "vpc_id" {
  description = "VPC to launch the instance into."
  type        = string
}

variable "subnet_id" {
  description = "Private subnet for the instance."
  type        = string
}

variable "alb_security_group_id" {
  description = "Security group of the ALB; the only source allowed to reach the instance."
  type        = string
}

variable "permissions_boundary_arn" {
  description = "IAM permissions boundary for the instance role (required by the CI apply role; see bootstrap/)."
  type        = string
  default     = null
}

variable "instance_type" {
  description = "EC2 instance type. Magnolia needs about 3 GB of RAM for heap plus JVM overhead."
  type        = string
}

variable "java_heap_mb" {
  description = "Tomcat JVM heap (-Xms/-Xmx) in MiB. Leave ~40% of RAM for metaspace, page cache and Nginx."
  type        = number
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size. Holds the OS, the exploded WAR and Magnolia's repository."
  type        = number
  default     = 20
}

variable "magnolia_version" {
  description = "Magnolia CE version."
  type        = string
}

variable "magnolia_war_url" {
  description = "Download URL of the Magnolia CE webapp WAR."
  type        = string
}

variable "magnolia_war_sha256" {
  description = "Expected SHA-256 of the WAR; provisioning aborts on mismatch."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.magnolia_war_sha256))
    error_message = "magnolia_war_sha256 must be a lowercase hex SHA-256 digest."
  }
}

variable "superuser_password_version" {
  description = "Bump to generate and store a new superuser password in SSM (the instance only reads it on first install)."
  type        = number
  default     = 1
}
