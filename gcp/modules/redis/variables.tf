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

variable "vpc_id" {
  type        = string
  description = "Full resource ID of the VPC: projects/{project}/global/networks/{name}"
}

# Passing module.networking.private_service_connection here carries the implicit
# dependency ensuring the PSA peering exists before Memorystore allocates an IP.
variable "private_service_connection" {
  type        = string
  description = "ID of the google_service_networking_connection; enforces creation order"
}

variable "tier" {
  type        = string
  default     = "BASIC"
  description = "BASIC (single node, no failover) or STANDARD_HA (replica + auto-failover)"
}

variable "memory_size_gb" {
  type        = number
  default     = 1
  description = "Redis memory size in GiB"
}

variable "redis_version" {
  type        = string
  default     = "REDIS_7_0"
  description = "Redis version: REDIS_6_X | REDIS_7_0"
}

variable "enable_read_replica" {
  type        = bool
  default     = false
  description = "Enable read replicas (only valid when tier = STANDARD_HA)"
}

variable "replica_count" {
  type        = number
  default     = 1
  description = "Number of read replicas (1–5); only used when enable_read_replica = true"
}

variable "transit_encryption_mode" {
  type        = string
  default     = "DISABLED"
  description = "DISABLED (VPC isolation only) or SERVER_AUTHENTICATION (TLS required by clients)"
}

variable "gke_namespace" {
  type        = string
  default     = "apps"
  description = "Kubernetes namespace of the ServiceAccount that will impersonate the Redis GSA"
}

variable "redis_ksa_name" {
  type        = string
  default     = "redis-sa"
  description = "Name of the Kubernetes ServiceAccount that will impersonate the Redis GSA"
}

variable "labels" {
  type    = map(string)
  default = {}
}
