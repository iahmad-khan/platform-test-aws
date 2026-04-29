terraform {
  backend "gcs" {
    # Pre-create this bucket before running terraform init.
    # gsutil mb -p <project> gs://gke-platform-tfstate-prod
    bucket = "gke-platform-tfstate-prod"
    prefix = "gcp/prod/terraform.tfstate"
  }
}
