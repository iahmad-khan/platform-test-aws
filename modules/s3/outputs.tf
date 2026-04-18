output "app_bucket_id" {
  value = aws_s3_bucket.app.id
}

output "app_bucket_arn" {
  value = aws_s3_bucket.app.arn
}

output "app_bucket_domain_name" {
  value = aws_s3_bucket.app.bucket_regional_domain_name
}

output "logs_bucket_id" {
  value = aws_s3_bucket.logs.id
}

output "logs_bucket_arn" {
  value = aws_s3_bucket.logs.arn
}

output "logs_bucket_domain_name" {
  value = aws_s3_bucket.logs.bucket_regional_domain_name
}
