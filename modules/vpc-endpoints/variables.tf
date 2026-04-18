variable "name" {
  type        = string
  description = "Resource name prefix"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs where interface endpoints are placed"
}

variable "endpoint_sg_id" {
  type        = string
  description = "Security group ID for VPC interface endpoints (allows 443 from VPC)"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Common tags applied to all resources"
}
