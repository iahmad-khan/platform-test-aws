terraform {
  backend "gcs" {
    # State is stored in the prod GCP project — separate from dev.
    # Create the bucket once before terraform init:
    #   gcloud storage buckets create gs://gke-platform-tfstate-prod \
    #     --project=YOUR_PROD_PROJECT_ID \
    #     --location=us-east1 \
    #     --uniform-bucket-level-access
    project = "YOUR_PROD_PROJECT_ID"   # keep in sync with project_id in terraform.tfvars
    bucket  = "gke-platform-tfstate-prod"
    prefix  = "gcp/prod/terraform.tfstate"
  }
}
