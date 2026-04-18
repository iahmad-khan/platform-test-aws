variable "name" {
  type        = string
  description = "Resource name prefix"
}

variable "cloudfront_distribution_arn" {
  type        = string
  description = "CloudFront distribution ARN to protect"
}

variable "route53_zone_id" {
  type        = string
  description = "Route53 hosted zone ID to protect"
}

variable "nat_eip_arns" {
  type        = list(string)
  description = "EIP ARNs for NAT Gateways — Shield protects them at the network edge"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Common tags applied to all resources"
}
