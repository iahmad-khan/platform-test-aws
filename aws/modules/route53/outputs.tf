output "zone_id" {
  value = data.aws_route53_zone.this.zone_id
}

output "zone_arn" {
  value = data.aws_route53_zone.this.arn
}

output "acm_certificate_arn_cloudfront" {
  value       = aws_acm_certificate_validation.cloudfront.certificate_arn
  description = "Validated ACM cert ARN in us-east-1 — use for CloudFront"
}

output "acm_certificate_arn_regional" {
  value       = aws_acm_certificate_validation.regional.certificate_arn
  description = "Validated regional ACM cert ARN — use for ALB HTTPS listener"
}
