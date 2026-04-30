variable "project_id" {
  type        = string
  description = "GCP project ID for the dev environment — must be a dedicated project, not shared with prod"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid GCP project ID (6-30 chars, lowercase letters, digits, hyphens)."
  }
}

variable "region" {
  type    = string
  default = "us-east1"
}

variable "master_authorized_networks" {
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default     = []
  description = "CIDRs allowed to reach the GKE API server"
}
