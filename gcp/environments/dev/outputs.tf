output "gke_cluster_name" {
  value = module.gke.cluster_name
}

output "gke_cluster_endpoint" {
  value     = module.gke.cluster_endpoint
  sensitive = true
}

output "cloud_sql_instance" {
  value     = module.cloud_sql.instance_connection_name
  sensitive = true
}

output "cloud_sql_private_ip" {
  value     = module.cloud_sql.private_ip_address
  sensitive = true
}

output "storage_bucket" {
  value = module.cloud_storage.bucket_name
}

output "artifact_registry_url" {
  value       = module.artifact_registry.repository_url
  description = "Prefix for all image tags pushed to this environment"
}

output "cloud_armor_policy" {
  value       = module.cloud_armor.security_policy_name
  description = "Set this in the BackendConfig spec.securityPolicy.name field"
}

output "redis_host" {
  value     = module.redis.host
  sensitive = true
}

output "redis_port" {
  value = module.redis.port
}

output "redis_auth_secret" {
  value       = module.redis.auth_secret_id
  description = "Fetch the AUTH token: gcloud secrets versions access latest --secret=<this value>"
}

output "redis_gsa_email" {
  value       = module.redis.redis_gsa_email
  description = "Annotate your Kubernetes ServiceAccount with this GSA email for Workload Identity"
}

output "kubeconfig_command" {
  value = "gcloud container clusters get-credentials ${module.gke.cluster_name} --region ${var.region} --project ${var.project_id}"
}
