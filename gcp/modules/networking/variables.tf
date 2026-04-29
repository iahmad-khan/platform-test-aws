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

variable "nodes_cidr" {
  type    = string
  default = "10.0.0.0/20"
}

variable "pods_cidr" {
  type    = string
  default = "10.4.0.0/14"
}

variable "services_cidr" {
  type    = string
  default = "10.8.0.0/20"
}

variable "master_cidr" {
  type        = string
  default     = "172.16.0.0/28"
  description = "CIDR block assigned to the GKE control plane; must not overlap with VPC ranges"
}

variable "labels" {
  type    = map(string)
  default = {}
}
