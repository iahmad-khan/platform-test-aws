variable "destination_account_id" {
  type        = string
  description = "AWS account ID of the destination registry (e.g. prod account)"
}

variable "destination_region" {
  type        = string
  description = "AWS region of the destination registry"
}

variable "repo_prefix_filter" {
  type        = string
  default     = ""
  description = "Replicate only repos whose name starts with this prefix. Empty string = replicate all repos (PREFIX_MATCH with \"\" matches everything)"
}
