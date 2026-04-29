variable "project_id" {
  type = string
}

variable "name" {
  type = string
}

variable "gke_namespace" {
  type        = string
  default     = "apps"
  description = "Kubernetes namespace where workload identity-bound ServiceAccounts live"
}

variable "cloud_sql_ksa_name" {
  type        = string
  default     = "cloud-sql-sa"
  description = "Name of the Kubernetes ServiceAccount that will impersonate the Cloud SQL GSA"
}

variable "cloud_storage_ksa_name" {
  type        = string
  default     = "cloud-storage-sa"
  description = "Name of the Kubernetes ServiceAccount that will impersonate the Cloud Storage GSA"
}

variable "labels" {
  type    = map(string)
  default = {}
}
