variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-east1"
}

variable "repository_id" {
  type        = string
  description = "Repository name (part of the image URL: <region>-docker.pkg.dev/<project>/<repository_id>/<image>)"
}

variable "node_service_account_email" {
  type        = string
  description = "GKE node SA email; granted artifactregistry.reader for passwordless image pulls"
}

variable "cicd_service_account_email" {
  type        = string
  default     = ""
  description = "Optional CI/CD SA email granted artifactregistry.writer to push images"
}

variable "labels" {
  type    = map(string)
  default = {}
}
