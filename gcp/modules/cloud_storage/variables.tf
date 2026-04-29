variable "project_id" {
  type = string
}

variable "name" {
  type        = string
  description = "Suffix appended to project_id to form the globally unique bucket name"
}

variable "location" {
  type        = string
  default     = "US-EAST1"
  description = "GCS bucket location; use a region (US-EAST1) or multi-region (US)"
}

variable "force_destroy" {
  type        = bool
  default     = false
  description = "Allow Terraform to delete the bucket even when it contains objects (dev only)"
}

variable "log_expiry_days" {
  type        = number
  default     = 90
  description = "Delete all object versions after this many days"
}

variable "cloud_storage_gsa_email" {
  type        = string
  description = "Email of the GSA granted storage.objectAdmin via Workload Identity"
}

variable "labels" {
  type    = map(string)
  default = {}
}
