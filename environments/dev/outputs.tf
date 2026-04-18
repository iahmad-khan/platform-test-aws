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

output "alb_controller_role_arn" {
  value = module.irsa.alb_controller_role_arn
}

output "ecr_repository_url" {
  value       = module.ecr.repository_url
  description = "docker push <url>:<tag>"
}

output "ecr_clickhouse_repository_url" {
  value       = module.ecr_clickhouse.repository_url
  description = "docker tag clickhouse:9.1.1 <url>:9.1.1 && docker push <url>:9.1.1"
}

output "demo_app_test_commands" {
  value = <<-EOT
    # Port-forward and test:
    ${module.demo_app.kubectl_port_forward}
    curl http://localhost:8080/health
    curl http://localhost:8080/s3
    curl http://localhost:8080/translate
  EOT
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
