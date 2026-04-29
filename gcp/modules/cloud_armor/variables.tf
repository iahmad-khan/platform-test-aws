variable "project_id" {
  type = string
}

variable "name" {
  type = string
}

variable "allowed_ip_ranges" {
  type        = list(string)
  default     = []
  description = "CIDRs that bypass WAF and rate-limiting (e.g. internal VPN, monitoring probes)"
}

variable "denied_ip_ranges" {
  type        = list(string)
  default     = []
  description = "CIDRs to block unconditionally before any other rule is evaluated"
}

variable "rate_limit_count" {
  type        = number
  default     = 500
  description = "Maximum number of requests per interval before throttling kicks in"
}

variable "rate_limit_interval_sec" {
  type        = number
  default     = 60
  description = "Rolling window in seconds for the rate-limit threshold"
}

variable "labels" {
  type    = map(string)
  default = {}
}
