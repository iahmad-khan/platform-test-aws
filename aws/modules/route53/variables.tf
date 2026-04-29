variable "domain_name" {
  type        = string
  description = "Apex domain name — must match an existing Route53 hosted zone (e.g. example.com)"
}

variable "alb_dns_name" {
  type        = string
  description = "ALB DNS name for A-alias record"
}

variable "alb_hosted_zone_id" {
  type        = string
  description = "ALB canonical hosted zone ID for alias record"
}

variable "cloudfront_domain_name" {
  type        = string
  description = "CloudFront distribution domain name"
}

variable "cloudfront_hosted_zone_id" {
  type        = string
  default     = "Z2FDTNDATAQYW2"
  description = "CloudFront global hosted zone ID (constant across all distributions)"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Common tags applied to all resources"
}
