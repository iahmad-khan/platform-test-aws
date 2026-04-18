variable "name" {
  type        = string
  description = "Resource name prefix"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Common tags applied to all resources"
}
