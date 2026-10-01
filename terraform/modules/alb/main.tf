# AWS-managed list of CloudFront origin-facing IP ranges.
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "this" {
  name        = "${var.name}-alb"
  description = "ALB: HTTP from CloudFront only"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-alb" }
}

# Layer 1: the network. Only CloudFront edge IPs can open a connection to the ALB at all.
resource "aws_vpc_security_group_ingress_rule" "http_from_cloudfront" {
  security_group_id = aws_security_group.this.id
  description       = "HTTP from CloudFront origin-facing ranges"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
}

# Targets are addressed by VPC CIDR rather than the instance SG, which keeps this module
# independent of the app module (the app SG already references this one).
resource "aws_vpc_security_group_egress_rule" "http_to_targets" {
  security_group_id = aws_security_group.this.id
  description       = "HTTP to targets inside the VPC"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_lb" "this" {
  name               = var.name
  load_balancer_type = "application"
  internal           = false
  subnets            = var.public_subnet_ids
  security_groups    = [aws_security_group.this.id]

  drop_invalid_header_fields = true
  idle_timeout               = 120
}

resource "aws_lb_target_group" "this" {
  name     = "${var.name}-magnolia"
  vpc_id   = var.vpc_id
  port     = 80
  protocol = "HTTP"

  deregistration_delay = 30

  # Magnolia's own readiness probe (JCR datastore + superuser setup), served through Nginx,
  # so a healthy target means the whole Nginx -> Tomcat -> Magnolia chain is up.
  health_check {
    path                = var.health_check_path
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_target_group_attachment" "this" {
  target_group_arn = aws_lb_target_group.this.arn
  target_id        = var.target_instance_id
  port             = 80
}

# Layer 2: the request. Other AWS customers' CloudFront distributions share the same edge IPs,
# so the ALB only forwards requests carrying a secret header that only our distribution sets.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }
}

resource "aws_lb_listener_rule" "from_cloudfront" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 1

  condition {
    http_header {
      http_header_name = var.origin_verify_header_name
      values           = [var.origin_verify_header_value]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}
