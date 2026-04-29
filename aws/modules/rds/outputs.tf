output "cluster_endpoint" {
  value       = aws_rds_cluster.this.endpoint
  description = "Writer endpoint"
}

output "reader_endpoint" {
  value       = aws_rds_cluster.this.reader_endpoint
  description = "Reader endpoint (round-robin across read replicas)"
}

output "cluster_id" {
  value = aws_rds_cluster.this.id
}

output "database_name" {
  value = aws_rds_cluster.this.database_name
}

output "master_user_secret_arn" {
  value       = aws_rds_cluster.this.master_user_secret[0].secret_arn
  description = "Secrets Manager ARN for the master user password"
}
