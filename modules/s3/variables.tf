variable "name" {
  type        = string
  description = "Resource name prefix"
}

variable "env" {
  type        = string
  description = "Environment name (dev, staging, prod)"
}

variable "cloudfront_distribution_arn" {
  type        = string
  default     = ""
  description = "CloudFront distribution ARN for OAC bucket policy (set after CF is created)"
}

variable "log_expiry_days" {
  type        = number
  default     = 90
  description = "Lifecycle expiry for logs bucket objects"
}

variable "force_destroy_logs" {
  type        = bool
  default     = false
  description = "Allow Terraform to destroy logs bucket even if non-empty (dev only)"
}

variable "cors_allowed_origins" {
  type        = list(string)
  default     = ["*"]
  description = "CORS allowed origins for the app assets bucket"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Common tags applied to all resources"
}
