output "vpc_self_link" {
  value = google_compute_network.vpc.self_link
}

output "subnet_self_link" {
  value = google_compute_subnetwork.nodes.self_link
}

output "pods_range_name" {
  value = "${var.name}-pods"
}

output "services_range_name" {
  value = "${var.name}-services"
}

# Passing this ID into cloud_sql creates an implicit Terraform dependency,
# ensuring the PSA peering is established before Cloud SQL is created.
output "private_service_connection" {
  value = google_service_networking_connection.private_service.id
}
