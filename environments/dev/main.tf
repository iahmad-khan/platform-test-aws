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

# ── 3. VPC Interface Endpoints (ECR, STS) ─────────────────────────────────────
# Keeps ECR traffic inside the VPC — kubelet credential provider uses instance
# metadata + these endpoints to authenticate without imagePullSecrets.
module "vpc_endpoints" {
  source = "../../modules/vpc-endpoints"

  name               = local.name
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  endpoint_sg_id     = module.security_groups.vpc_endpoint_sg_id
  tags               = local.common_tags
}

# ── 4. Base IAM Roles (no OIDC dependency) ────────────────────────────────────
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

  endpoint_public_access = true
  public_access_cidrs    = ["0.0.0.0/0"]
  route53_zone_arn       = module.route53.zone_arn
  node_tenant_label      = "amd-hosts"
  enable_kube_prometheus = true
  enable_argocd          = true
  tags                   = local.common_tags
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

# ── 9. ECR Repositories ───────────────────────────────────────────────────────
module "ecr" {
  source = "../../modules/ecr"

  name                           = "aws-ecr-${local.env}"
  image_tag_mutability           = "MUTABLE"
  scan_on_push                   = true
  lifecycle_untagged_expiry_days = 7
  lifecycle_tagged_keep_count    = 20
  # Allow only the staging CI promoter user to pull (least-privilege cross-account)
  cross_account_pull_arns        = ["arn:aws:iam::${var.staging_account_id}:user/ci/platform-ci-ecr-promoter"]
  tags                           = local.common_tags
}

module "ecr_clickhouse" {
  source = "../../modules/ecr"

  name                           = "clickhouse"
  image_tag_mutability           = "IMMUTABLE"
  scan_on_push                   = true
  lifecycle_untagged_expiry_days = 7
  lifecycle_tagged_keep_count    = 10
  cross_account_pull_arns        = ["arn:aws:iam::${var.staging_account_id}:user/ci/platform-ci-ecr-promoter"]
  tags                           = local.common_tags
}

# ── 10. Pod Identity — IAM + association ──────────────────────────────────────
module "pod_identity" {
  source = "../../modules/pod-identity"

  name                 = local.name
  cluster_name         = module.eks.cluster_name
  namespace            = "demo-app"
  service_account_name = "demo-app-sa"
  s3_bucket_arns       = [module.s3.app_bucket_arn, module.s3.logs_bucket_arn]
  tags                 = local.common_tags
}

# ── 11. Demo App Deployment ────────────────────────────────────────────────────
module "demo_app" {
  source = "../../modules/demo-app"

  namespace            = "demo-app"
  service_account_name = "demo-app-sa"
  s3_bucket_name       = module.s3.app_bucket_id
  aws_region           = var.aws_region
  replicas             = 1
  tags                 = local.common_tags

  depends_on = [module.pod_identity]
}

# ── 12. CloudFront Distribution ───────────────────────────────────────────────
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
