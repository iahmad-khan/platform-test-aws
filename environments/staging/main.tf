locals {
  env  = "staging"
  name = "platform-${local.env}"
  azs  = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]

  common_tags = {
    Environment = local.env
    Project     = "platform"
    ManagedBy   = "terraform"
  }
}

module "vpc" {
  source = "../../modules/vpc"

  name                    = local.name
  vpc_cidr                = "10.20.0.0/16"
  azs                     = local.azs
  public_subnet_cidrs     = ["10.20.1.0/24", "10.20.2.0/24", "10.20.3.0/24"]
  private_subnet_cidrs    = ["10.20.11.0/24", "10.20.12.0/24", "10.20.13.0/24"]
  single_nat_gateway      = true
  enable_flow_logs        = true
  flow_log_retention_days = 14
  tags                    = local.common_tags
}

module "security_groups" {
  source   = "../../modules/security-groups"
  name     = local.name
  vpc_id   = module.vpc.vpc_id
  vpc_cidr = module.vpc.vpc_cidr_block
  tags     = local.common_tags
}

module "iam" {
  source = "../../modules/iam"
  name   = local.name
  tags   = local.common_tags
}

module "eks" {
  source = "../../modules/eks"

  name               = local.name
  kubernetes_version = var.kubernetes_version
  cluster_role_arn   = module.iam.cluster_role_arn
  node_role_arn      = module.iam.node_role_arn
  private_subnet_ids = module.vpc.private_subnet_ids
  cluster_sg_id      = module.security_groups.eks_cluster_sg_id
  node_sg_id         = module.security_groups.eks_node_sg_id

  endpoint_public_access  = true
  public_access_cidrs     = ["0.0.0.0/0"]
  alb_controller_role_arn = module.irsa.alb_controller_role_arn
  node_tenant_label       = "amd-hosts"
  enable_kube_prometheus  = true
  enable_argocd           = true
  tags                    = local.common_tags
}

module "irsa" {
  source = "../../modules/irsa"

  name              = local.name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  route53_zone_arn  = module.route53.zone_arn
  tags              = local.common_tags
}

module "rds" {
  source = "../../modules/rds"

  name               = local.name
  database_name      = "appdb"
  instance_count     = 2
  instance_class     = "db.serverless"
  min_capacity       = 1
  max_capacity       = 8
  private_subnet_ids = module.vpc.private_subnet_ids
  rds_sg_id          = module.security_groups.rds_sg_id

  backup_retention_period               = 3
  deletion_protection                   = false
  skip_final_snapshot                   = true
  apply_immediately                     = false
  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  tags                                  = local.common_tags
}

module "s3" {
  source = "../../modules/s3"

  name                        = "platform"
  env                         = local.env
  cloudfront_distribution_arn = module.cloudfront.distribution_arn
  log_expiry_days             = 60
  force_destroy_logs          = false
  cors_allowed_origins        = ["https://${var.domain_name}", "https://www.${var.domain_name}"]
  tags                        = local.common_tags
}

module "route53" {
  source = "../../modules/route53"
  providers = { aws.us_east_1 = aws.us_east_1 }

  domain_name               = var.domain_name
  alb_dns_name              = ""
  alb_hosted_zone_id        = ""
  cloudfront_domain_name    = module.cloudfront.distribution_domain_name
  cloudfront_hosted_zone_id = module.cloudfront.distribution_hosted_zone_id
  tags                      = local.common_tags
}

module "cloudfront" {
  source = "../../modules/cloudfront"

  name                    = local.name
  s3_bucket_domain_name   = module.s3.app_bucket_domain_name
  s3_bucket_arn           = module.s3.app_bucket_arn
  alb_dns_name            = ""
  acm_certificate_arn     = module.route53.acm_certificate_arn_cloudfront
  domain_aliases          = [var.domain_name, "www.${var.domain_name}"]
  logs_bucket_domain_name = module.s3.logs_bucket_domain_name
  price_class             = "PriceClass_100"
  tags                    = local.common_tags
}
