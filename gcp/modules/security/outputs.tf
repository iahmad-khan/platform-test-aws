output "node_service_account_email" {
  value = google_service_account.gke_node.email
}

output "cloud_sql_gsa_email" {
  value = google_service_account.cloud_sql.email
}

output "cloud_storage_gsa_email" {
  value = google_service_account.cloud_storage.email
}
