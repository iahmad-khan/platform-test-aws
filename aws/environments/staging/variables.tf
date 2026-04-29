variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "domain_name" {
  type        = string
  description = "Apex domain name matching an existing Route53 hosted zone"
}

variable "kubernetes_version" {
  type    = string
  default = "1.31"
}

variable "dev_account_id" {
  type        = string
  description = "AWS account ID of the dev environment"
}

variable "prod_account_id" {
  type        = string
  description = "AWS account ID of the prod environment — used for ECR replication destination"
}
