locals {
  env  = "dev"
  name = "gke-${local.env}"

  common_labels = {
    environment = local.env
    project     = "gke-platform"
    managed_by  = "terraform"
  }
}

# ── Security & APIs ───────────────────────────────────────────────────────────
# Must run first: enables GCP APIs and creates all GSAs / Workload Identity bindings.

module "security" {
  source = "../../modules/security"

  project_id             = var.project_id
  name                   = local.name
  gke_namespace          = "apps"
  cloud_sql_ksa_name     = "cloud-sql-sa"
  cloud_storage_ksa_name = "cloud-storage-sa"
  labels                 = local.common_labels
}

# ── Networking ────────────────────────────────────────────────────────────────

module "networking" {
  source = "../../modules/networking"

  project_id    = var.project_id
  region        = var.region
  name          = local.name
  nodes_cidr    = "10.0.0.0/20"
  pods_cidr     = "10.4.0.0/14"
  services_cidr = "10.8.0.0/20"
  master_cidr   = "172.16.0.0/28"
  labels        = local.common_labels

  depends_on = [module.security]
}

# ── GKE Cluster ───────────────────────────────────────────────────────────────

module "gke" {
  source = "../../modules/gke"

  project_id                 = var.project_id
  region                     = var.region
  name                       = local.name
  network_self_link          = module.networking.vpc_self_link
  subnetwork_self_link       = module.networking.subnet_self_link
  pods_range_name            = module.networking.pods_range_name
  services_range_name        = module.networking.services_range_name
  node_service_account_email = module.security.node_service_account_email
  master_authorized_networks = var.master_authorized_networks

  release_channel             = "REGULAR"
  deletion_protection         = false
  system_node_count           = 1
  system_node_machine_type    = "e2-standard-2"
  cpu_min                     = 4
  cpu_max                     = 1000
  memory_min                  = 16
  memory_max                  = 1024
  gpu_t4_max                  = 4
  gpu_a100_max                = 0
  gpu_l4_max                  = 4
  enable_binary_authorization = false

  # Regional cluster — nodes and NAP pools spread across all zones in var.region.
  # Restrict to 2 zones in dev to reduce system node count (1 node × 2 zones = 2 nodes).
  node_locations = ["${var.region}-b", "${var.region}-c"]

  # Blue-green upgrade settings (faster cadence acceptable in dev)
  blue_green_soak_duration       = "120s"
  blue_green_batch_percentage    = 0.50
  blue_green_batch_soak_duration = "60s"

  labels = local.common_labels
}

# ── Cloud SQL ─────────────────────────────────────────────────────────────────

module "cloud_sql" {
  source = "../../modules/cloud_sql"

  project_id                 = var.project_id
  region                     = var.region
  name                       = local.name
  vpc_self_link              = module.networking.vpc_self_link
  private_service_connection = module.networking.private_service_connection
  database_name              = "appdb"
  tier                       = "db-g1-small"
  availability_type          = "ZONAL"
  retained_backups           = 3
  deletion_protection        = false
  enable_read_replica        = false
  cloud_sql_gsa_email        = module.security.cloud_sql_gsa_email
  labels                     = local.common_labels
}

# ── Cloud Storage ─────────────────────────────────────────────────────────────

module "cloud_storage" {
  source = "../../modules/cloud_storage"

  project_id              = var.project_id
  name                    = "${local.name}-assets"
  location                = "US-EAST1"
  force_destroy           = true
  log_expiry_days         = 30
  cloud_storage_gsa_email = module.security.cloud_storage_gsa_email
  labels                  = local.common_labels
}

# ── Cloud Armor ───────────────────────────────────────────────────────────────
# Creates the security policy. Attach it to GKE services via BackendConfig
# (see gcp/modules/cloud_armor/outputs.tf for the YAML to apply).

module "cloud_armor" {
  source = "../../modules/cloud_armor"

  project_id              = var.project_id
  name                    = local.name
  rate_limit_count        = 500
  rate_limit_interval_sec = 60
  labels                  = local.common_labels
}

# ── Artifact Registry ─────────────────────────────────────────────────────────
# GKE nodes can pull images without imagePullSecrets.
# Push images to: us-east1-docker.pkg.dev/<project_id>/gke-dev-app/<image>:<tag>

module "artifact_registry" {
  source = "../../modules/artifact_registry"

  project_id                 = var.project_id
  region                     = var.region
  repository_id              = "${local.name}-app"
  node_service_account_email = module.security.node_service_account_email
  labels                     = local.common_labels
}

# ── Redis (Memorystore) ───────────────────────────────────────────────────────
# BASIC tier (no failover) for dev. AUTH token stored in Secret Manager;
# pods retrieve it at runtime via Workload Identity — no static secrets.

module "redis" {
  source = "../../modules/redis"

  project_id                 = var.project_id
  region                     = var.region
  name                       = local.name
  vpc_id                     = module.networking.vpc_id
  private_service_connection = module.networking.private_service_connection
  tier                       = "BASIC"
  memory_size_gb             = 1
  redis_version              = "REDIS_7_0"
  enable_read_replica        = false
  transit_encryption_mode    = "DISABLED"
  gke_namespace              = "apps"
  redis_ksa_name             = "redis-sa"
  labels                     = local.common_labels
}
