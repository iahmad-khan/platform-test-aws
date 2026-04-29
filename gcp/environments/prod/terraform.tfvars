project_id = "your-prod-gcp-project-id"
region     = "us-east1"

# Restrict to your VPN or office CIDR — never use 0.0.0.0/0 in prod
master_authorized_networks = [
  {
    cidr_block   = "10.0.0.0/8"
    display_name = "internal-vpn"
  }
]

# CIDRs that bypass Cloud Armor WAF and rate limiting (monitoring, internal traffic)
trusted_ip_ranges = []

# Set to a CI/CD service account to allow image pushes from your pipeline
cicd_service_account_email = ""
