output "repository_id" {
  value = google_artifact_registry_repository.registry.repository_id
}

output "repository_url" {
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.registry.repository_id}"
  description = "Base URL for pushing and pulling images; append /<image>:<tag>"
}
