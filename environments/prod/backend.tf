terraform {
  backend "s3" {
    bucket       = "platform-test-terraform-state-663130434961-us-east-1-an"
    key          = "prod/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
