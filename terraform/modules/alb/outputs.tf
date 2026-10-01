output "security_group_id" {
  description = "Security group of the ALB."
  value       = aws_security_group.this.id
}

output "dns_name" {
  description = "Public DNS name of the ALB (CloudFront origin)."
  value       = aws_lb.this.dns_name
}

output "arn_suffix" {
  description = "ARN suffix of the ALB, for CloudWatch metrics."
  value       = aws_lb.this.arn_suffix
}

output "target_group_arn_suffix" {
  description = "ARN suffix of the target group, for CloudWatch metrics."
  value       = aws_lb_target_group.this.arn_suffix
}
