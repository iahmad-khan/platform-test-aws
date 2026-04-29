locals {
  env  = "prod"
  name = "gke-${local.env}"

  common_labels = {
    environment = local.env
    project     = "gke-platform"
    managed_by  = "terraform"
  }
}

# ── Security & APIs ───────────────────────────────────────────────────────────

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
  nodes_cidr    = "10.10.0.0/20"
  pods_cidr     = "10.16.0.0/14"
  services_cidr = "10.20.0.0/20"
  master_cidr   = "172.16.1.0/28"
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

  release_channel             = "STABLE"
  deletion_protection         = true
  system_node_count           = 3
  system_node_machine_type    = "e2-standard-4"
  cpu_min                     = 12
  cpu_max                     = 1000
  memory_min                  = 48
  memory_max                  = 1024
  gpu_t4_max                  = 16
  gpu_a100_max                = 8
  gpu_l4_max                  = 16
  enable_binary_authorization = true

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
  tier                       = "db-custom-2-7680"
  availability_type          = "REGIONAL"
  retained_backups           = 3
  transaction_log_retention_days = 7
  deletion_protection        = true
  enable_read_replica        = true
  replica_tier               = "db-custom-2-3840"
  cloud_sql_gsa_email        = module.security.cloud_sql_gsa_email
  labels                     = local.common_labels
}

# ── Cloud Storage ─────────────────────────────────────────────────────────────

module "cloud_storage" {
  source = "../../modules/cloud_storage"

  project_id              = var.project_id
  name                    = "${local.name}-assets"
  location                = "US-EAST1"
  force_destroy           = false
  log_expiry_days         = 365
  cloud_storage_gsa_email = module.security.cloud_storage_gsa_email
  labels                  = local.common_labels
}

# ── Cloud Armor ───────────────────────────────────────────────────────────────
# Stricter rate limit in prod. Adaptive Protection auto-mitigates DDoS attacks.
# See gcp/modules/cloud_armor/outputs.tf for how to attach to GKE ingress.

module "cloud_armor" {
  source = "../../modules/cloud_armor"

  project_id              = var.project_id
  name                    = local.name
  rate_limit_count        = 200
  rate_limit_interval_sec = 60
  # Add VPN/monitoring CIDRs to skip WAF and rate-limit for internal traffic
  allowed_ip_ranges       = var.trusted_ip_ranges
  labels                  = local.common_labels
}

# ── Artifact Registry ─────────────────────────────────────────────────────────

module "artifact_registry" {
  source = "../../modules/artifact_registry"

  project_id                 = var.project_id
  region                     = var.region
  repository_id              = "${local.name}-app"
  node_service_account_email = module.security.node_service_account_email
  cicd_service_account_email = var.cicd_service_account_email
  labels                     = local.common_labels
}

# ── Redis (Memorystore) ───────────────────────────────────────────────────────
# STANDARD_HA tier with one read replica and TLS for prod.
# AUTH token stored in Secret Manager; pods retrieve it via Workload Identity.

module "redis" {
  source = "../../modules/redis"

  project_id                 = var.project_id
  region                     = var.region
  name                       = local.name
  vpc_id                     = module.networking.vpc_id
  private_service_connection = module.networking.private_service_connection
  tier                       = "STANDARD_HA"
  memory_size_gb             = 4
  redis_version              = "REDIS_7_0"
  enable_read_replica        = true
  replica_count              = 1
  transit_encryption_mode    = "SERVER_AUTHENTICATION"
  gke_namespace              = "apps"
  redis_ksa_name             = "redis-sa"
  labels                     = local.common_labels
}
