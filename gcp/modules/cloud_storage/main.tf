resource "google_storage_bucket" "bucket" {
  project                     = var.project_id
  name                        = "${var.project_id}-${var.name}"
  location                    = var.location
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  force_destroy               = var.force_destroy
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  # Keep only the 3 most recent non-current versions then delete the rest
  lifecycle_rule {
    condition {
      num_newer_versions = 3
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      age        = var.log_expiry_days
      with_state = "ANY"
    }
    action {
      type = "Delete"
    }
  }

  labels = var.labels
}

resource "google_storage_bucket_iam_member" "workload_identity" {
  bucket = google_storage_bucket.bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.cloud_storage_gsa_email}"
}
