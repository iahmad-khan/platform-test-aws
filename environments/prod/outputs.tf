output "vpc_id" {
  value = module.vpc.vpc_id
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value     = module.eks.cluster_endpoint
  sensitive = true
}

output "rds_endpoint" {
  value = module.rds.cluster_endpoint
}

output "rds_reader_endpoint" {
  value = module.rds.reader_endpoint
}

output "rds_master_secret_arn" {
  value       = module.rds.master_user_secret_arn
  description = "Fetch DB password: aws secretsmanager get-secret-value --secret-id <arn>"
}

output "app_bucket_name" {
  value = module.s3.app_bucket_id
}

output "cloudfront_domain" {
  value = module.cloudfront.distribution_domain_name
}

output "cloudfront_distribution_id" {
  value = module.cloudfront.distribution_id
}

output "alb_controller_role_arn" {
  value = module.irsa.alb_controller_role_arn
}

output "external_dns_role_arn" {
  value = module.irsa.external_dns_role_arn
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
