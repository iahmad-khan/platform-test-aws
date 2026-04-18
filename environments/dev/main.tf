locals {
  env  = "dev"
  name = "platform-${local.env}"
  azs  = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]

  common_tags = {
    Environment = local.env
    Project     = "platform"
    ManagedBy   = "terraform"
  }
}

# ── 1. VPC ─────────────────────────────────────────────────────────────────────
module "vpc" {
  source = "../../modules/vpc"

  name                 = local.name
  vpc_cidr             = "10.10.0.0/16"
  azs                  = local.azs
  public_subnet_cidrs  = ["10.10.1.0/24", "10.10.2.0/24", "10.10.3.0/24"]
  private_subnet_cidrs = ["10.10.11.0/24", "10.10.12.0/24", "10.10.13.0/24"]
  single_nat_gateway   = true
  enable_flow_logs     = true
  flow_log_retention_days = 7
  tags                 = local.common_tags
}

# ── 2. Security Groups ─────────────────────────────────────────────────────────
module "security_groups" {
  source   = "../../modules/security-groups"
  name     = local.name
  vpc_id   = module.vpc.vpc_id
  vpc_cidr = module.vpc.vpc_cidr_block
  tags     = local.common_tags
}

# ── 3. Base IAM Roles (no OIDC dependency) ────────────────────────────────────
module "iam" {
  source = "../../modules/iam"
  name   = local.name
  tags   = local.common_tags
}

# ── 4. EKS Cluster ────────────────────────────────────────────────────────────
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

# ── 5. IRSA Roles (require EKS OIDC output) ───────────────────────────────────
module "irsa" {
  source = "../../modules/irsa"

  name              = local.name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  route53_zone_arn  = module.route53.zone_arn
  tags              = local.common_tags
}

# ── 6. RDS Aurora Serverless v2 ───────────────────────────────────────────────
module "rds" {
  source = "../../modules/rds"

  name               = local.name
  database_name      = "appdb"
  instance_count     = 1
  instance_class     = "db.serverless"
  min_capacity       = 0.5
  max_capacity       = 4
  private_subnet_ids = module.vpc.private_subnet_ids
  rds_sg_id          = module.security_groups.rds_sg_id

  backup_retention_period              = 1
  deletion_protection                  = false
  skip_final_snapshot                  = true
  apply_immediately                    = true
  performance_insights_enabled         = false
  tags                                 = local.common_tags
}

# ── 7. S3 Buckets ─────────────────────────────────────────────────────────────
module "s3" {
  source = "../../modules/s3"

  name                        = "platform"
  env                         = local.env
  cloudfront_distribution_arn = module.cloudfront.distribution_arn
  log_expiry_days             = 30
  force_destroy_logs          = true
  cors_allowed_origins        = ["*"]
  tags                        = local.common_tags
}

# ── 8. Route53 + ACM Certificates ─────────────────────────────────────────────
module "route53" {
  source = "../../modules/route53"
  providers = { aws.us_east_1 = aws.us_east_1 }

  domain_name               = var.domain_name
  alb_dns_name              = ""  # Set after first ALB is created by LBC
  alb_hosted_zone_id        = ""
  cloudfront_domain_name    = module.cloudfront.distribution_domain_name
  cloudfront_hosted_zone_id = module.cloudfront.distribution_hosted_zone_id
  tags                      = local.common_tags
}

# ── 9. CloudFront Distribution ────────────────────────────────────────────────
module "cloudfront" {
  source = "../../modules/cloudfront"

  name                    = local.name
  s3_bucket_domain_name   = module.s3.app_bucket_domain_name
  s3_bucket_arn           = module.s3.app_bucket_arn
  alb_dns_name            = ""  # Set after LBC creates ALB
  acm_certificate_arn     = module.route53.acm_certificate_arn_cloudfront
  domain_aliases          = [var.domain_name, "www.${var.domain_name}"]
  logs_bucket_domain_name = module.s3.logs_bucket_domain_name
  price_class             = "PriceClass_100"
  tags                    = local.common_tags
}
