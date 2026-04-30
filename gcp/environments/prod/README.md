# Environment: prod

Production environment for the GKE platform stack. All resources are sized for availability and durability: deletion protection is on everywhere, Cloud SQL runs in REGIONAL HA mode with a read replica, Redis uses STANDARD_HA with TLS and a read replica, Binary Authorization is enforced, and Cloud Armor rate limits are tighter.

## What this environment deploys

| Module | Key settings |
|---|---|
| security | Same as dev — 9 GCP APIs, node SA, all GSAs + Workload Identity bindings |
| networking | Custom VPC, node subnet with secondary IP ranges, Cloud Router + NAT, PSA peering |
| gke | STABLE release channel, 3 system nodes (e2-standard-4), NAP up to 1000 vCPU / 1 TiB RAM, Binary Authorization enforced |
| cloud_sql | REGIONAL PostgreSQL 16 (db-custom-2-7680), automatic HA failover, read replica (db-custom-2-3840), 3 count-based backups, deletion_protection=true |
| cloud_storage | Private versioned bucket (`{project_id}-gke-prod-assets`), force_destroy disabled, 365-day expiry |
| cloud_armor | Layer 7 WAF + DDoS policy, stricter rate limit 200 req/IP/60 s, optional IP allowlist |
| artifact_registry | Docker repository `gke-prod-app`, passwordless pulls via node SA, optional CI/CD push SA |
| redis | STANDARD_HA tier (4 GiB, REDIS_7_0), TLS (SERVER_AUTHENTICATION), 1 read replica, AUTH token in Secret Manager |

## Differences from dev

| Aspect | dev | prod |
|---|---|---|
| GKE release channel | REGULAR | STABLE |
| System node count | 1 × e2-standard-2 | 3 × e2-standard-4 |
| Binary Authorization | disabled | enforced |
| GKE deletion_protection | false | true |
| Cloud SQL tier | db-g1-small | db-custom-2-7680 |
| Cloud SQL availability | ZONAL | REGIONAL (auto-failover) |
| Cloud SQL read replica | no | yes (db-custom-2-3840) |
| Cloud SQL deletion_protection | false | true |
| Cloud Storage force_destroy | true | false |
| Cloud Storage expiry | 30 days | 365 days |
| Cloud Armor rate limit | 500 req/60 s | 200 req/60 s |
| Cloud Armor IP allowlist | none | `trusted_ip_ranges` variable |
| Artifact Registry CI/CD push | none | `cicd_service_account_email` variable |
| Redis tier | BASIC | STANDARD_HA |
| Redis memory | 1 GiB | 4 GiB |
| Redis TLS | disabled | SERVER_AUTHENTICATION |
| Redis read replica | no | 1 replica |

## IP address plan

| Range | CIDR | Used for |
|---|---|---|
| Nodes | `10.10.0.0/20` | GKE node primary IPs |
| Pods | `10.16.0.0/14` | Pod alias IPs (secondary range) |
| Services | `10.20.0.0/20` | ClusterIP services (secondary range) |
| Master | `172.16.1.0/28` | GKE control plane (private endpoint) |

These CIDRs are non-overlapping with dev (`10.0.x`, `10.4.x`, `10.8.x`) — safe to peer or interconnect both environments.

## Prerequisites

1. A dedicated GCP project for production with billing enabled.
2. The identity running Terraform must have `roles/owner` or `roles/editor` + `roles/resourcemanager.projectIamAdmin`.
3. A GCS bucket for remote state (separate from dev):
   ```bash
   gcloud storage buckets create gs://gke-platform-tfstate-prod \
     --project=YOUR_PROD_PROJECT \
     --location=us-east1 \
     --uniform-bucket-level-access
   ```
4. `terraform >= 1.5`, `google` provider `>= 5.0`, `google-beta` provider `>= 5.0`.
5. For Binary Authorization: container images must be signed before deploy. Configure an attestor in the GCP console or via the `binary-authorization` CLI before enforcing.

## Backend configuration

[backend.tf](backend.tf):
```hcl
terraform {
  backend "gcs" {
    bucket = "gke-platform-tfstate-prod"
    prefix = "gcp/prod/terraform.tfstate"
  }
}
```

## Variables

Set these in `terraform.tfvars`:

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `project_id` | `string` | Yes | — | GCP project ID |
| `region` | `string` | No | `"us-east1"` | Region for all resources |
| `master_authorized_networks` | `list(object)` | No | `[]` | CIDRs allowed to reach the GKE API server — restrict to VPN/office IPs |
| `trusted_ip_ranges` | `list(string)` | No | `[]` | CIDRs that bypass Cloud Armor WAF and rate-limiting (VPN, monitoring probes) |
| `cicd_service_account_email` | `string` | No | `""` | CI/CD SA email granted push access to Artifact Registry |

Example `terraform.tfvars`:
```hcl
project_id = "my-prod-project-456"
region     = "us-east1"

master_authorized_networks = [
  { cidr_block = "10.100.0.0/16", display_name = "vpn" },
  { cidr_block = "203.0.113.0/24", display_name = "office" }
]

trusted_ip_ranges = [
  "10.100.0.0/16",   # VPN — skip WAF and rate-limit
  "35.191.0.0/16",   # GCP health check probes
  "130.211.0.0/22",  # GCP health check probes
]

cicd_service_account_email = "github-actions@my-prod-project-456.iam.gserviceaccount.com"
```

## Deploy

```bash
cd gcp/environments/prod

terraform init
terraform plan -out=prod.tfplan
terraform apply prod.tfplan
```

Modules deploy in dependency order automatically:
`security` → `networking` → `gke`, `cloud_sql`, `cloud_storage`, `cloud_armor`, `artifact_registry`, `redis`

First apply takes ~20 minutes (GKE cluster + REGIONAL Cloud SQL with replica dominate).

## Outputs

| Output | Sensitive | Description |
|---|---|---|
| `gke_cluster_name` | No | Cluster name (`gke-prod`) |
| `gke_cluster_endpoint` | Yes | GKE API server IP |
| `cloud_sql_instance` | Yes | `PROJECT:REGION:INSTANCE` — pass to Cloud SQL Auth Proxy (primary) |
| `cloud_sql_private_ip` | Yes | Private IP of the PostgreSQL primary |
| `cloud_sql_replica_connection_name` | Yes | Auth Proxy connection name for the read replica |
| `storage_bucket` | No | GCS bucket name |
| `artifact_registry_url` | No | Base image URL: `us-east1-docker.pkg.dev/{project}/gke-prod-app` |
| `cloud_armor_policy` | No | Policy name — use in `BackendConfig` YAML |
| `redis_host` | Yes | Private IP of the Redis primary |
| `redis_port` | No | Redis port (`6379`) |
| `redis_read_endpoint` | Yes | Private IP of the Redis read endpoint |
| `redis_auth_secret` | No | Secret Manager secret ID for the AUTH token |
| `redis_gsa_email` | No | GSA email to annotate the `redis-sa` KSA |
| `kubeconfig_command` | No | Full `gcloud` command to configure kubectl |

```bash
terraform output
terraform output -raw kubeconfig_command | bash
```

## Post-apply checks

```bash
# 1. Connect kubectl
$(terraform output -raw kubeconfig_command)

# 2. Verify 3 system nodes are Ready
kubectl get nodes -l cloud.google.com/gke-nodepool=system

# 3. Verify Binary Authorization policy is active
gcloud container binauthz policy export --project=YOUR_PROD_PROJECT

# 4. Verify Cloud SQL REGIONAL HA
gcloud sql instances describe gke-prod-pg \
  --project=YOUR_PROD_PROJECT \
  --format="value(settings.availabilityType)"
# Expected: REGIONAL

# 5. Verify Redis STANDARD_HA
gcloud redis instances describe gke-prod-redis \
  --region=us-east1 \
  --project=YOUR_PROD_PROJECT \
  --format="value(tier)"
# Expected: STANDARD_HA

# 6. Verify Redis TLS — retrieve the server CA certificate
gcloud redis instances describe gke-prod-redis \
  --region=us-east1 \
  --format="value(serverCaCerts[0].cert)" > redis-ca.pem

# 7. Verify AUTH token in Secret Manager
gcloud secrets versions access latest \
  --secret=$(terraform output -raw redis_auth_secret) \
  --project=YOUR_PROD_PROJECT

# 8. Verify Cloud Armor policy is attached after you deploy GKE services
gcloud compute backend-services list --global --project=YOUR_PROD_PROJECT
```

## Destroy

**Do not destroy prod without explicit authorization.**

Because `deletion_protection = true` is set on the GKE cluster and Cloud SQL instances, Terraform will refuse to delete them. You must first disable deletion protection, then destroy:

```bash
# Step 1 — disable deletion protection
# Edit main.tf: set deletion_protection = false on module.gke and module.cloud_sql
# Then apply the change:
terraform apply -target=module.gke -target=module.cloud_sql

# Step 2 — destroy everything
terraform destroy
```

The Cloud Storage bucket has `force_destroy = false` in prod. Terraform will refuse to delete it while it contains objects. Either empty it manually first or change `force_destroy = true` in main.tf and re-apply before destroying.
