# ── APIs ──────────────────────────────────────────────────────────────────────
# redis.googleapis.com is also listed in the security module, but enabling it
# here makes this module self-contained if deployed independently.

resource "google_project_service" "redis" {
  project            = var.project_id
  service            = "redis.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "secretmanager" {
  project            = var.project_id
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

# ── Memorystore Redis instance ────────────────────────────────────────────────
# Uses Private Service Access so the instance shares the existing PSA peering
# that was set up by the networking module for Cloud SQL. No extra VPC peering
# is created, and no reserved_ip_range block is required.

resource "google_redis_instance" "cache" {
  project        = var.project_id
  name           = "${var.name}-redis"
  display_name   = "${var.name} Redis Cache"
  region         = var.region
  tier           = var.tier
  memory_size_gb = var.memory_size_gb
  redis_version  = var.redis_version

  authorized_network = var.vpc_id       # projects/{project}/global/networks/{name}
  connect_mode       = "PRIVATE_SERVICE_ACCESS"

  auth_enabled            = true
  transit_encryption_mode = var.transit_encryption_mode

  # Read replicas are only valid on STANDARD_HA tier.
  # When enable_read_replica = true, reads can be distributed across replicas
  # using the read_endpoint output (separate host:port from the primary).
  replica_count      = var.tier == "STANDARD_HA" && var.enable_read_replica ? var.replica_count : 0
  read_replicas_mode = var.tier == "STANDARD_HA" && var.enable_read_replica ? "READ_REPLICAS_ENABLED" : "READ_REPLICAS_DISABLED"

  maintenance_policy {
    weekly_maintenance_window {
      day = "SUNDAY"
      start_time {
        hours   = 3
        minutes = 0
        seconds = 0
        nanos   = 0
      }
    }
  }

  labels = var.labels

  # PSA peering must exist before Memorystore can allocate a private IP.
  # Passing private_service_connection as a variable value carries this implicit
  # dependency without needing depends_on on a variable (which Terraform disallows).
  depends_on = [
    google_project_service.redis,
    google_project_service.secretmanager,
  ]
}

# ── Secret Manager — Redis AUTH token ─────────────────────────────────────────
# GCP generates and rotates the AUTH string for the instance. We store it in
# Secret Manager so pods can fetch it at runtime using their Workload Identity.

resource "google_secret_manager_secret" "redis_auth" {
  project   = var.project_id
  secret_id = "${var.name}-redis-auth"

  replication {
    auto {}
  }

  labels = var.labels

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "redis_auth" {
  secret      = google_secret_manager_secret.redis_auth.id
  secret_data = google_redis_instance.cache.auth_string
}

# ── Workload Identity GSA ─────────────────────────────────────────────────────
# This GSA is granted secretAccessor on the AUTH secret so that Kubernetes pods
# annotated with this GSA can fetch the Redis password without static secrets.

resource "google_service_account" "redis" {
  project      = var.project_id
  account_id   = "${var.name}-redis"
  display_name = "Redis Workload Identity GSA"
}

resource "google_secret_manager_secret_iam_member" "redis_sa_accessor" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.redis_auth.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.redis.email}"
}

# Binds the Kubernetes ServiceAccount to the GSA.
# The KSA must be annotated with:
#   iam.gke.io/gcp-service-account: <redis_gsa_email>
resource "google_service_account_iam_member" "redis_wi" {
  service_account_id = google_service_account.redis.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.gke_namespace}/${var.redis_ksa_name}]"
}
