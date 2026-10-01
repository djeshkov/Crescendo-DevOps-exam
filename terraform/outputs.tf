output "magnolia_url" {
  description = "Magnolia AdminCentral through CloudFront."
  value       = "https://${module.cdn.domain_name}/.magnolia/admincentral"
}

output "cloudfront_domain_name" {
  description = "CloudFront domain name."
  value       = module.cdn.domain_name
}

output "alb_dns_name" {
  description = "ALB DNS name (answers 403 to anything that did not come through CloudFront)."
  value       = module.alb.dns_name
}

output "instance_id" {
  description = "Magnolia EC2 instance ID (for `aws ssm start-session`)."
  value       = module.app.instance_id
}

output "superuser_password_command" {
  description = "Command that prints the Magnolia superuser password."
  value       = "aws ssm get-parameter --with-decryption --name ${module.app.superuser_password_parameter} --query Parameter.Value --output text --region ${var.aws_region}"
}
