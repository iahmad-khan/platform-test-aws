# ── Primary instance ──────────────────────────────────────────────────────────

resource "google_sql_database_instance" "instance" {
  project             = var.project_id
  name                = "${var.name}-pg"
  database_version    = "POSTGRES_16"
  region              = var.region
  deletion_protection = var.deletion_protection

  settings {
    tier              = var.tier
    availability_type = var.availability_type
    disk_autoresize   = true
    disk_type         = "PD_SSD"

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.vpc_self_link
      # Allows Cloud SQL Auth Proxy and IAM DB auth from within the VPC
      enable_private_path_for_google_cloud_services = true
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = "02:00"
      transaction_log_retention_days = var.transaction_log_retention_days

      backup_retention_settings {
        # Cloud SQL automated backup count; user requested keeping only last 3.
        retained_backups = var.retained_backups
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = 7 # Sunday
      hour         = 3
      update_track = "stable"
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = false
    }

    database_flags { name = "log_checkpoints";    value = "on" }
    database_flags { name = "log_connections";    value = "on" }
    database_flags { name = "log_disconnections"; value = "on" }
    database_flags { name = "log_lock_waits";     value = "on" }

    user_labels = var.labels
  }
}

# ── Read replica ──────────────────────────────────────────────────────────────
# Created only when enable_read_replica = true. Shares the same VPC as the
# primary but runs in a separate zone (or region if replica_region differs).
# Replicas cannot have backups; they inherit the primary's PITR log chain.

resource "google_sql_database_instance" "replica" {
  count = var.enable_read_replica ? 1 : 0

  project              = var.project_id
  name                 = "${var.name}-pg-replica"
  database_version     = "POSTGRES_16"
  region               = var.replica_region != "" ? var.replica_region : var.region
  master_instance_name = google_sql_database_instance.instance.name
  deletion_protection  = var.deletion_protection

  replica_configuration {
    failover_target = false
  }

  settings {
    tier            = var.replica_tier != "" ? var.replica_tier : var.tier
    availability_type = "ZONAL"
    disk_autoresize = true
    disk_type       = "PD_SSD"

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.vpc_self_link
      enable_private_path_for_google_cloud_services = true
    }

    # Replicas must not have backup_configuration enabled
    backup_configuration {
      enabled                        = false
      point_in_time_recovery_enabled = false
    }

    user_labels = var.labels
  }
}

# ── Database & IAM user ───────────────────────────────────────────────────────

resource "google_sql_database" "db" {
  project  = var.project_id
  instance = google_sql_database_instance.instance.name
  name     = var.database_name
}

# IAM-based database user tied to the Workload Identity GSA — no password needed.
# The pod authenticates using its Google identity token via the Cloud SQL Auth Proxy.
resource "google_sql_user" "iam_user" {
  project  = var.project_id
  instance = google_sql_database_instance.instance.name
  name     = trimsuffix(var.cloud_sql_gsa_email, ".gserviceaccount.com")
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}
