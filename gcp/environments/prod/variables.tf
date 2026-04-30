variable "project_id" {
  type        = string
  description = "GCP project ID for the prod environment — must be a dedicated project, not shared with dev"

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
  description = "CIDRs allowed to reach the GKE API server — restrict to VPN/office IPs in prod"
}

variable "trusted_ip_ranges" {
  type        = list(string)
  default     = []
  description = "CIDRs that bypass Cloud Armor WAF and rate-limiting (e.g. VPN, monitoring probes)"
}

variable "cicd_service_account_email" {
  type        = string
  default     = ""
  description = "Optional CI/CD SA email granted push access to Artifact Registry"
}
