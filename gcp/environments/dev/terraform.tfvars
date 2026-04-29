project_id = "your-dev-gcp-project-id"
region     = "us-east1"

master_authorized_networks = [
  {
    cidr_block   = "0.0.0.0/0"
    display_name = "all (dev only — restrict in prod)"
  }
]
