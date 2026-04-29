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

variable "network_self_link" {
  type = string
}

variable "subnetwork_self_link" {
  type = string
}

variable "pods_range_name" {
  type = string
}

variable "services_range_name" {
  type = string
}

variable "master_ipv4_cidr" {
  type        = string
  default     = "172.16.0.0/28"
  description = "CIDR for the control-plane VPC peering; must not overlap any subnet range"
}

variable "node_service_account_email" {
  type = string
}

variable "master_authorized_networks" {
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default     = []
  description = "CIDRs allowed to reach the public API server endpoint"
}

variable "enable_binary_authorization" {
  type    = bool
  default = false
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "release_channel" {
  type        = string
  default     = "REGULAR"
  description = "RAPID | REGULAR | STABLE"
}

variable "system_node_count" {
  type        = number
  default     = 1
  description = "Number of nodes in the system node pool per zone"
}

variable "system_node_machine_type" {
  type    = string
  default = "e2-standard-4"
}

variable "cpu_min" {
  type    = number
  default = 4
}

variable "cpu_max" {
  type        = number
  default     = 1000
  description = "Maximum total vCPUs NAP may provision cluster-wide"
}

variable "memory_min" {
  type    = number
  default = 16
}

variable "memory_max" {
  type        = number
  default     = 1024
  description = "Maximum total memory (GiB) NAP may provision cluster-wide (~1 TB)"
}

variable "gpu_t4_max" {
  type        = number
  default     = 16
  description = "Maximum NVIDIA T4 GPUs NAP may provision; 0 disables T4 nodes"
}

variable "gpu_a100_max" {
  type        = number
  default     = 8
  description = "Maximum NVIDIA A100 GPUs NAP may provision; 0 disables A100 nodes"
}

variable "gpu_l4_max" {
  type        = number
  default     = 16
  description = "Maximum NVIDIA L4 GPUs NAP may provision; 0 disables L4 nodes"
}

variable "maintenance_start_time" {
  type    = string
  default = "2025-01-01T00:00:00Z"
}

variable "maintenance_end_time" {
  type    = string
  default = "2025-01-01T06:00:00Z"
}

variable "labels" {
  type    = map(string)
  default = {}
}
