variable "name" {
  type        = string
  description = "Resource name prefix"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where security groups are created"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block — used for intra-VPC rules and DNS egress"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Common tags applied to all resources"
}
