# Artifact Registry Docker repository (modern replacement for GCR / gcr.io).
# Image URL format: <region>-docker.pkg.dev/<project>/<repository_id>/<image>:<tag>
#
# Passwordless image pulls from GKE:
#   The GKE node service account is granted reader access at the repository level.
#   Because the kubelet uses the node SA to authenticate with Artifact Registry,
#   all pods on the cluster can pull images without imagePullSecrets.
#   No per-pod ServiceAccount annotation is required.

resource "google_artifact_registry_repository" "registry" {
  project       = var.project_id
  location      = var.region
  repository_id = var.repository_id
  format        = "DOCKER"
  description   = "Docker image repository: ${var.repository_id}"

  labels = var.labels
}

# Grant the GKE node SA read access at the repository level.
# This enables passwordless image pulls for all pods on the cluster.
resource "google_artifact_registry_repository_iam_member" "node_sa_reader" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.registry.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${var.node_service_account_email}"
}

# Optional CI/CD service account granted push access.
# Set cicd_service_account_email to enable; leave empty to skip.
resource "google_artifact_registry_repository_iam_member" "cicd_writer" {
  count = var.cicd_service_account_email != "" ? 1 : 0

  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.registry.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${var.cicd_service_account_email}"
}
