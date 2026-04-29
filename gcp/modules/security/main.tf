# Enable all GCP APIs required by the stack before any other module runs
resource "google_project_service" "apis" {
  for_each = toset([
    "container.googleapis.com",
    "sqladmin.googleapis.com",
    "storage.googleapis.com",
    "iam.googleapis.com",
    "servicenetworking.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "artifactregistry.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# ── GKE Node Service Account ─────────────────────────────────────────────────

resource "google_service_account" "gke_node" {
  project      = var.project_id
  account_id   = "${var.name}-gke-node"
  display_name = "GKE Node SA"
}

resource "google_project_iam_member" "gke_node_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/artifactregistry.reader",
    "roles/storage.objectViewer",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_node.email}"
}

# ── Cloud SQL Workload Identity GSA ──────────────────────────────────────────

resource "google_service_account" "cloud_sql" {
  project      = var.project_id
  account_id   = "${var.name}-cloud-sql"
  display_name = "Cloud SQL Workload Identity GSA"
}

resource "google_project_iam_member" "cloud_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.cloud_sql.email}"
}

# Binds the Kubernetes ServiceAccount to the Google SA via Workload Identity
resource "google_service_account_iam_member" "cloud_sql_wi" {
  service_account_id = google_service_account.cloud_sql.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.gke_namespace}/${var.cloud_sql_ksa_name}]"
}

# ── Cloud Storage Workload Identity GSA ──────────────────────────────────────

resource "google_service_account" "cloud_storage" {
  project      = var.project_id
  account_id   = "${var.name}-cloud-storage"
  display_name = "Cloud Storage Workload Identity GSA"
}

# Binds the Kubernetes ServiceAccount to the Google SA via Workload Identity
resource "google_service_account_iam_member" "cloud_storage_wi" {
  service_account_id = google_service_account.cloud_storage.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.gke_namespace}/${var.cloud_storage_ksa_name}]"
}
