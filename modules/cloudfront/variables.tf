variable "name" {
  type        = string
  description = "Resource name prefix"
}

variable "s3_bucket_domain_name" {
  type        = string
  description = "S3 app bucket regional domain name (origin for static assets)"
}

variable "s3_bucket_arn" {
  type        = string
  description = "S3 app bucket ARN (for OAC policy)"
}

variable "alb_dns_name" {
  type        = string
  description = "ALB DNS name (origin for /api/* dynamic traffic)"
}

variable "acm_certificate_arn" {
  type        = string
  description = "ACM certificate ARN in us-east-1 (required for CloudFront)"
}

variable "domain_aliases" {
  type        = list(string)
  description = "Custom domain aliases e.g. ['example.com', 'www.example.com']"
}

variable "logs_bucket_domain_name" {
  type        = string
  description = "S3 logs bucket domain name for CloudFront access logs"
}

variable "price_class" {
  type        = string
  default     = "PriceClass_100"
  description = "CloudFront price class: PriceClass_100, PriceClass_200, PriceClass_All"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Common tags applied to all resources"
}
