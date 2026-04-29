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

output "kubeconfig_command" {
  value = "gcloud container clusters get-credentials ${module.gke.cluster_name} --region ${var.region} --project ${var.project_id}"
}
