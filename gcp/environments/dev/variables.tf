variable "project_id" {
  type        = string
  description = "GCP project ID to deploy into"
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
