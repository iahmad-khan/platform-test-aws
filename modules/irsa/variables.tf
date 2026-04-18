variable "name" {
  type        = string
  description = "Resource name prefix"
}

variable "oidc_provider_arn" {
  type        = string
  description = "EKS OIDC provider ARN (from module.eks output)"
}

variable "oidc_provider_url" {
  type        = string
  description = "EKS OIDC provider URL without https:// prefix"
}

variable "route53_zone_arn" {
  type        = string
  default     = "*"
  description = "Route53 hosted zone ARN for external-dns write permissions"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Common tags applied to all resources"
}
