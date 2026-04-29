output "cluster_name" {
  value = google_container_cluster.cluster.name
}

output "cluster_endpoint" {
  value     = google_container_cluster.cluster.endpoint
  sensitive = true
}

output "cluster_ca_certificate" {
  value     = google_container_cluster.cluster.master_auth[0].cluster_ca_certificate
  sensitive = true
}

output "cluster_id" {
  value = google_container_cluster.cluster.id
}
