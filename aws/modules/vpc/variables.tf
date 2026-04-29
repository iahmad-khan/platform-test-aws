variable "name" {
  type        = string
  description = "Resource name prefix"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block"
}

variable "azs" {
  type        = list(string)
  description = "List of availability zones"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for public subnets, one per AZ"
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for private subnets, one per AZ"
}

variable "single_nat_gateway" {
  type        = bool
  default     = false
  description = "Use a single NAT GW instead of one per AZ (cost saving for non-prod)"
}

variable "enable_flow_logs" {
  type        = bool
  default     = true
  description = "Enable VPC Flow Logs to CloudWatch"
}

variable "flow_log_retention_days" {
  type        = number
  default     = 30
  description = "CloudWatch log retention for flow logs (days)"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Common tags applied to all resources"
}
