terraform {
  backend "s3" {
    bucket       = "platform-terraform-state-<STAGING_ACCOUNT_ID>-us-east-1"
    key          = "staging/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
