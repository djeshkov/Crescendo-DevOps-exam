variable "project" {
  description = "Project name; prefixes resource names together with the environment."
  type        = string
  default     = "magnolia"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-west-1"
}

variable "vpc_cidr" {
  description = "VPC CIDR block (/16)."
  type        = string
  default     = "10.20.0.0/16"
}

variable "single_nat_gateway" {
  description = "One shared NAT gateway (cheap, dev) vs one per AZ (HA, prod)."
  type        = bool
  default     = true
}

variable "instance_type" {
  description = "EC2 instance type for Magnolia (8 GB RAM; free-tier eligible on new AWS accounts)."
  type        = string
  default     = "m7i-flex.large"
}

variable "java_heap_mb" {
  description = "Tomcat JVM heap in MiB."
  type        = number
  default     = 4096
}

variable "magnolia_version" {
  description = "Magnolia CE version to install."
  type        = string
  default     = "6.4.10"
}

variable "magnolia_war_sha256" {
  description = "SHA-256 of magnolia-community-webapp-<version>.war (from Magnolia's Nexus search API)."
  type        = string
  default     = "aafd8aff9bb1aad640c3902ed6191a1145ddfdf4d6ca3627e3d02f88fcda76fa"
}
