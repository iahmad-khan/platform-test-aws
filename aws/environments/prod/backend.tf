terraform {
  backend "s3" {
    bucket       = "platform-terraform-state-<PROD_ACCOUNT_ID>-us-east-1"
    key          = "prod/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
