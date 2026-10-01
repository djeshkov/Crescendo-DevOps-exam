data "aws_caller_identity" "current" {}

locals {
  name = "${var.project}-${var.environment}"

  # Created by bootstrap/. The CI apply role may only create IAM roles that carry it.
  permissions_boundary_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.project}-workload-boundary"

  magnolia_war_url = "https://nexus.magnolia-cms.com/repository/public/info/magnolia/bundle/magnolia-community-webapp/${var.magnolia_version}/magnolia-community-webapp-${var.magnolia_version}.war"

  origin_verify_header_name = "X-Origin-Verify"
}

# Shared secret between CloudFront and the ALB. It has to live in state: CloudFront needs the
# plain value in its config and the ALB rule matches on it.
resource "random_password" "origin_verify" {
  length  = 32
  special = false
}

module "network" {
  source = "./modules/network"

  name               = local.name
  vpc_cidr           = var.vpc_cidr
  single_nat_gateway = var.single_nat_gateway
}

module "app" {
  source = "./modules/app"

  name                  = local.name
  vpc_id                = module.network.vpc_id
  subnet_id             = module.network.private_subnet_ids[0]
  alb_security_group_id = module.alb.security_group_id

  permissions_boundary_arn = local.permissions_boundary_arn

  instance_type       = var.instance_type
  java_heap_mb        = var.java_heap_mb
  magnolia_version    = var.magnolia_version
  magnolia_war_url    = local.magnolia_war_url
  magnolia_war_sha256 = var.magnolia_war_sha256
}

module "alb" {
  source = "./modules/alb"

  name               = local.name
  vpc_id             = module.network.vpc_id
  vpc_cidr           = module.network.vpc_cidr
  public_subnet_ids  = module.network.public_subnet_ids
  target_instance_id = module.app.instance_id

  origin_verify_header_name  = local.origin_verify_header_name
  origin_verify_header_value = random_password.origin_verify.result
}

module "cdn" {
  source = "./modules/cdn"

  name         = local.name
  alb_dns_name = module.alb.dns_name

  origin_verify_header_name  = local.origin_verify_header_name
  origin_verify_header_value = random_password.origin_verify.result
}
