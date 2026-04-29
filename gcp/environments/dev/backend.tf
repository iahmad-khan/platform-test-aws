terraform {
  backend "gcs" {
    # Pre-create this bucket before running terraform init.
    # gsutil mb -p <project> gs://gke-platform-tfstate-dev
    bucket = "gke-platform-tfstate-dev"
    prefix = "gcp/dev/terraform.tfstate"
  }
}
