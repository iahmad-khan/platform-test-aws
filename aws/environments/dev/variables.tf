variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "domain_name" {
  type        = string
  description = "Apex domain name matching an existing Route53 hosted zone (e.g. example.com)"
}

variable "kubernetes_version" {
  type    = string
  default = "1.31"
}

variable "staging_account_id" {
  type        = string
  description = "AWS account ID of the staging environment — dev ECR grants staging pull access for CI promotion"
}
