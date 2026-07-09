data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # Default the ECR registry to this account's registry in the target region.
  image_registry = var.image_registry != "" ? var.image_registry : "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com"

  # Full imagePrefix the chart concatenates as <imagePrefix>/<service>:<tag>.
  image_prefix = "${local.image_registry}/${var.image_repo_prefix}"

  tags = merge({
    "app.kubernetes.io/part-of" = "agent-shield"
    "managed-by"                = "terraform"
  }, var.tags)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = "${var.name_prefix}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  # /20 private (workloads + RDS), /24 public (ALB + NAT).
  private_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i + 48)]

  enable_nat_gateway   = true
  single_nat_gateway   = true # one NAT keeps trial cost down; set false for HA egress
  enable_dns_hostnames = true

  # Tags the AWS Load Balancer Controller relies on for subnet auto-discovery.
  public_subnet_tags = {
    "kubernetes.io/role/elb"                       = "1"
    "kubernetes.io/cluster/${var.name_prefix}-eks" = "shared"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"              = "1"
    "kubernetes.io/cluster/${var.name_prefix}-eks" = "shared"
  }

  tags = local.tags
}
