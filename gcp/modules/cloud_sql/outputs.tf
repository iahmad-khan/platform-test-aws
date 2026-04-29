output "instance_name" {
  value = google_sql_database_instance.instance.name
}

output "instance_connection_name" {
  value     = google_sql_database_instance.instance.connection_name
  sensitive = true
}

output "private_ip_address" {
  value     = google_sql_database_instance.instance.private_ip_address
  sensitive = true
}

output "database_name" {
  value = google_sql_database.db.name
}

output "replica_connection_name" {
  value     = var.enable_read_replica ? google_sql_database_instance.replica[0].connection_name : null
  sensitive = true
}

output "replica_private_ip_address" {
  value     = var.enable_read_replica ? google_sql_database_instance.replica[0].private_ip_address : null
  sensitive = true
}
