variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-east1"
}

variable "name" {
  type = string
}

variable "vpc_self_link" {
  type = string
}

# Passing module.networking.private_service_connection here creates an implicit
# Terraform dependency, ensuring the PSA VPC peering exists before Cloud SQL.
variable "private_service_connection" {
  type        = string
  description = "ID of the google_service_networking_connection; used only for implicit dependency ordering"
}

variable "database_name" {
  type    = string
  default = "appdb"
}

variable "tier" {
  type        = string
  default     = "db-g1-small"
  description = "Cloud SQL machine tier, e.g. db-g1-small (dev) or db-custom-2-7680 (prod)"
}

variable "availability_type" {
  type        = string
  default     = "ZONAL"
  description = "ZONAL (dev) or REGIONAL (prod HA with automatic failover)"
}

variable "retained_backups" {
  type        = number
  default     = 3
  description = "Number of automated backups to keep (COUNT-based retention)"
}

variable "transaction_log_retention_days" {
  type        = number
  default     = 7
  description = "Days to retain transaction logs for point-in-time recovery"
}

variable "deletion_protection" {
  type    = bool
  default = false
}

variable "enable_read_replica" {
  type        = bool
  default     = false
  description = "Create a read replica in the same (or different) region"
}

variable "replica_tier" {
  type        = string
  default     = ""
  description = "Machine tier for the replica; defaults to the same tier as the primary"
}

variable "replica_region" {
  type        = string
  default     = ""
  description = "Region for the read replica; defaults to the same region as the primary"
}

variable "cloud_sql_gsa_email" {
  type        = string
  description = "Email of the GSA used for Workload Identity IAM database authentication"
}

variable "labels" {
  type    = map(string)
  default = {}
}
