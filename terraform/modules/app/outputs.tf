output "instance_id" {
  description = "ID of the Magnolia EC2 instance."
  value       = aws_instance.this.id
}

output "security_group_id" {
  description = "Security group of the Magnolia instance."
  value       = aws_security_group.this.id
}

output "superuser_password_parameter" {
  description = "SSM parameter holding the Magnolia superuser password."
  value       = aws_ssm_parameter.superuser_password.name
}
