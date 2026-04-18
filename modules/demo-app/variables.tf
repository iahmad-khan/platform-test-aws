variable "namespace" {
  type        = string
  default     = "demo-app"
  description = "Kubernetes namespace for the demo deployment"
}

variable "service_account_name" {
  type        = string
  default     = "demo-app-sa"
  description = "Service account name — must match the Pod Identity association"
}

variable "s3_bucket_name" {
  type        = string
  description = "S3 bucket name the demo app will list objects from"
}

variable "aws_region" {
  type        = string
  description = "AWS region passed to the demo app as an env var"
}

variable "replicas" {
  type        = number
  default     = 2
  description = "Number of demo app pod replicas"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Labels applied to all Kubernetes resources"
}
