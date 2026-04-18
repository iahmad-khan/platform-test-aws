locals {
  env  = "prod"
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
  vpc_cidr                = "10.30.0.0/16"
  azs                     = local.azs
  public_subnet_cidrs     = ["10.30.1.0/24", "10.30.2.0/24", "10.30.3.0/24"]
  private_subnet_cidrs    = ["10.30.11.0/24", "10.30.12.0/24", "10.30.13.0/24"]
  single_nat_gateway      = false   # One NAT GW per AZ for HA
  enable_flow_logs        = true
  flow_log_retention_days = 90
  tags                    = local.common_tags
}

module "security_groups" {
  source   = "../../modules/security-groups"
  name     = local.name
  vpc_id   = module.vpc.vpc_id
  vpc_cidr = module.vpc.vpc_cidr_block
  tags     = local.common_tags
}

module "vpc_endpoints" {
  source = "../../modules/vpc-endpoints"

  name               = local.name
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  endpoint_sg_id     = module.security_groups.vpc_endpoint_sg_id
  tags               = local.common_tags
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
  instance_count     = 3   # 1 writer + 2 readers
  instance_class     = "db.serverless"
  min_capacity       = 2
  max_capacity       = 64
  private_subnet_ids = module.vpc.private_subnet_ids
  rds_sg_id          = module.security_groups.rds_sg_id

  backup_retention_period               = 30
  deletion_protection                   = true
  skip_final_snapshot                   = false
  apply_immediately                     = false
  performance_insights_enabled          = true
  performance_insights_retention_period = 731
  tags                                  = local.common_tags
}

module "s3" {
  source = "../../modules/s3"

  name                        = "platform"
  env                         = local.env
  cloudfront_distribution_arn = module.cloudfront.distribution_arn
  log_expiry_days             = 365
  force_destroy_logs          = false
  cors_allowed_origins        = ["https://${var.domain_name}", "https://www.${var.domain_name}"]
  tags                        = local.common_tags
}

module "ecr" {
  source = "../../modules/ecr"

  name                           = "aws-ecr-${local.env}"
  image_tag_mutability           = "IMMUTABLE"
  scan_on_push                   = true
  lifecycle_untagged_expiry_days = 14
  lifecycle_tagged_keep_count    = 30
  # Images arrive via AWS ECR replication from staging — no repo-level
  # cross-account policy needed; access is controlled by the registry policy below.
  cross_account_pull_arns        = []
  tags                           = local.common_tags
}

module "ecr_clickhouse" {
  source = "../../modules/ecr"

  name                           = "clickhouse"
  image_tag_mutability           = "IMMUTABLE"
  scan_on_push                   = true
  lifecycle_untagged_expiry_days = 14
  lifecycle_tagged_keep_count    = 10
  cross_account_pull_arns        = []
  tags                           = local.common_tags
}

# Allow the staging registry to replicate images into this (prod) registry.
# ECR replication requires an explicit registry policy on the destination side.
data "aws_caller_identity" "current" {}

resource "aws_ecr_registry_policy" "allow_staging_replication" {
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowStagingReplication"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.staging_account_id}:root"
        }
        Action = [
          "ecr:CreateRepository",
          "ecr:ReplicateImage"
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/*"
      }
    ]
  })
}

module "pod_identity" {
  source = "../../modules/pod-identity"

  name                 = local.name
  cluster_name         = module.eks.cluster_name
  namespace            = "demo-app"
  service_account_name = "demo-app-sa"
  s3_bucket_arns       = [module.s3.app_bucket_arn, module.s3.logs_bucket_arn]
  tags                 = local.common_tags
}

module "demo_app" {
  source = "../../modules/demo-app"

  namespace            = "demo-app"
  service_account_name = "demo-app-sa"
  s3_bucket_name       = module.s3.app_bucket_id
  aws_region           = var.aws_region
  replicas             = 2
  tags                 = local.common_tags

  depends_on = [module.pod_identity]
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
  price_class             = "PriceClass_All"
  tags                    = local.common_tags
}
