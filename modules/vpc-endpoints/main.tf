data "aws_region" "current" {}

locals {
  svc = "com.amazonaws.${data.aws_region.current.name}"
}

# ECR API — used by kubelet credential provider (GetAuthorizationToken)
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = var.vpc_id
  service_name        = "${local.svc}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [var.endpoint_sg_id]
  private_dns_enabled = true
  tags                = merge(var.tags, { Name = "${var.name}-vpce-ecr-api" })
}

# ECR DKR — used for actual layer pulls (docker pull)
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = var.vpc_id
  service_name        = "${local.svc}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [var.endpoint_sg_id]
  private_dns_enabled = true
  tags                = merge(var.tags, { Name = "${var.name}-vpce-ecr-dkr" })
}

# STS — required for IRSA token exchange (GetAuthorizationToken uses STS internally)
resource "aws_vpc_endpoint" "sts" {
  vpc_id              = var.vpc_id
  service_name        = "${local.svc}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [var.endpoint_sg_id]
  private_dns_enabled = true
  tags                = merge(var.tags, { Name = "${var.name}-vpce-sts" })
}
