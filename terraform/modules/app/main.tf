data "aws_region" "current" {}

# Latest Amazon Linux 2023 at the time of first apply. The AMI is then held (see ignore_changes
# below) so a new AMI release doesn't silently replace the server; OS patches come from dnf, and
# moving to a new AMI is a deliberate `terraform apply -replace`.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ---- Superuser password ---------------------------------------------------------------------
# Ephemeral + write-only: the value is generated during apply and pushed straight to SSM,
# it is never stored in the Terraform state or plan.
ephemeral "random_password" "superuser" {
  length  = 24
  special = false
}

resource "aws_ssm_parameter" "superuser_password" {
  name        = "/${var.name}/magnolia/superuser-password"
  description = "Initial password of the Magnolia 'superuser' account."
  type        = "SecureString"

  value_wo         = ephemeral.random_password.superuser.result
  value_wo_version = var.superuser_password_version
}

# ---- IAM: SSM Session Manager instead of SSH + read its own password -------------------------
data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = "${var.name}-magnolia"
  assume_role_policy   = data.aws_iam_policy_document.assume_ec2.json
  permissions_boundary = var.permissions_boundary_arn
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "read_password" {
  statement {
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.superuser_password.arn]
  }
}

resource "aws_iam_role_policy" "read_password" {
  name   = "read-superuser-password"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.read_password.json
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.name}-magnolia"
  role = aws_iam_role.this.name
}

# ---- Network access: only the ALB may reach Nginx; no inbound SSH at all ----------------------
resource "aws_security_group" "this" {
  name        = "${var.name}-magnolia"
  description = "Magnolia instance: HTTP from the ALB only"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-magnolia" }
}

resource "aws_vpc_security_group_ingress_rule" "http_from_alb" {
  security_group_id            = aws_security_group.this.id
  description                  = "Nginx from the ALB"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = var.alb_security_group_id
}

# Egress goes out through the NAT: dnf, the Magnolia WAR download, SSM endpoints.
resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.this.id
  description       = "HTTPS to the internet via NAT"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "http" {
  security_group_id = aws_security_group.this.id
  description       = "HTTP for package mirrors"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

# ---- Instance -------------------------------------------------------------------------------
resource "aws_instance" "this" {
  ami                    = data.aws_ssm_parameter.al2023.insecure_value
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.this.id]
  iam_instance_profile   = aws_iam_instance_profile.this.name

  user_data = templatefile("${path.module}/templates/user-data.sh.tftpl", {
    aws_region                   = data.aws_region.current.region
    magnolia_version             = var.magnolia_version
    magnolia_war_url             = var.magnolia_war_url
    magnolia_war_sha256          = var.magnolia_war_sha256
    java_heap_mb                 = var.java_heap_mb
    superuser_password_parameter = aws_ssm_parameter.superuser_password.name
  })
  # Provisioning is first-boot only, so a changed script must mean a fresh instance —
  # otherwise the plan would show a change that never actually reaches the server.
  user_data_replace_on_change = true

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size_gb
    encrypted   = true
  }

  tags = { Name = "${var.name}-magnolia" }

  lifecycle {
    ignore_changes = [ami]
  }
}
