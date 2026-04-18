variable "name" {
  type        = string
  description = "ECR repository name"
}

variable "image_tag_mutability" {
  type        = string
  default     = "IMMUTABLE"
  description = "IMMUTABLE (prod recommendation) or MUTABLE"
}

variable "scan_on_push" {
  type        = bool
  default     = true
  description = "Enable enhanced image scanning on push"
}

variable "encryption_type" {
  type        = string
  default     = "AES256"
  description = "AES256 or KMS"
}

variable "lifecycle_untagged_expiry_days" {
  type        = number
  default     = 14
  description = "Days before untagged images are expired"
}

variable "lifecycle_tagged_keep_count" {
  type        = number
  default     = 30
  description = "Number of tagged images to keep (oldest are pruned)"
}

variable "cross_account_pull_arns" {
  type        = list(string)
  default     = []
  description = "Additional IAM principal ARNs (from other accounts) allowed to pull images. e.g. [\"arn:aws:iam::222222222222:root\"]"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Common tags applied to all resources"
}
