variable "name" {
  description = "Name prefix for all resources."
  type        = string
}

variable "alb_dns_name" {
  description = "DNS name of the ALB used as the origin."
  type        = string
}

variable "origin_verify_header_name" {
  description = "Header added to every origin request so the ALB can tell our distribution apart."
  type        = string
}

variable "origin_verify_header_value" {
  description = "Secret value of the origin verification header."
  type        = string
  sensitive   = true
}

variable "price_class" {
  description = "CloudFront price class (edge locations used)."
  type        = string
  default     = "PriceClass_100"
}
