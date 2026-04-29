variable "name" {
  type        = string
  description = "Resource name prefix"
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name — used for Pod Identity association"
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace the service account lives in"
}

variable "service_account_name" {
  type        = string
  description = "Kubernetes service account name to bind to the IAM role"
}

variable "s3_bucket_arns" {
  type        = list(string)
  description = "ARNs of S3 buckets pods need full access to"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Common tags applied to all resources"
}
