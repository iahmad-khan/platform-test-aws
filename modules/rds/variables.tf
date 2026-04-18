variable "name" {
  type        = string
  description = "Resource name prefix"
}

variable "engine_version" {
  type        = string
  default     = "16.2"
  description = "Aurora PostgreSQL engine version"
}

variable "database_name" {
  type        = string
  default     = "appdb"
  description = "Initial database name"
}

variable "instance_count" {
  type        = number
  default     = 2
  description = "Number of Aurora cluster instances (1 = writer only)"
}

variable "instance_class" {
  type        = string
  default     = "db.serverless"
  description = "Instance class — use db.serverless for Serverless v2"
}

variable "min_capacity" {
  type        = number
  default     = 1
  description = "Serverless v2 minimum ACU capacity"
}

variable "max_capacity" {
  type        = number
  default     = 8
  description = "Serverless v2 maximum ACU capacity"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for the DB subnet group"
}

variable "rds_sg_id" {
  type        = string
  description = "Security group ID applied to RDS cluster instances"
}

variable "backup_retention_period" {
  type        = number
  default     = 7
  description = "Automated backup retention in days"
}

variable "deletion_protection" {
  type        = bool
  default     = false
  description = "Prevent accidental cluster deletion"
}

variable "skip_final_snapshot" {
  type        = bool
  default     = false
  description = "Skip final snapshot on cluster deletion"
}

variable "apply_immediately" {
  type        = bool
  default     = false
  description = "Apply changes immediately (true for dev, false for staging/prod)"
}

variable "performance_insights_enabled" {
  type        = bool
  default     = false
  description = "Enable Performance Insights on instances"
}

variable "performance_insights_retention_period" {
  type        = number
  default     = 7
  description = "Performance Insights data retention in days (7 or 731)"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Common tags applied to all resources"
}
