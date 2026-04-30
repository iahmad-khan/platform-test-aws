# Environment: dev

Development environment for the GKE platform stack. Optimised for fast iteration: deletion protection is off, resources are sized small, and Cloud SQL runs in a single zone with no read replica. All 8 modules are wired together in dependency order.

## What this environment deploys

| Module | Key settings |
|---|---|
| security | Enables 9 GCP APIs, creates node SA, Cloud SQL / Cloud Storage / Redis GSAs + Workload Identity bindings |
| networking | Custom VPC, node subnet with secondary IP ranges, Cloud Router + NAT, PSA peering (shared by Cloud SQL and Redis) |
| gke | REGULAR release channel, 1 system node (e2-standard-2), NAP up to 1000 vCPU / 1 TiB RAM, Binary Authorization disabled |
| cloud_sql | ZONAL PostgreSQL 16 (db-g1-small), 3 count-based backups, no read replica |
| cloud_storage | Private versioned bucket (`{project_id}-gke-dev-assets`), force_destroy enabled, 30-day expiry |
| cloud_armor | Layer 7 WAF + DDoS policy, rate limit 500 req/IP/60 s |
| artifact_registry | Docker repository `gke-dev-app`, passwordless pulls via node SA |
| redis | BASIC tier (1 GiB, REDIS_7_0), no TLS, no replica, AUTH token in Secret Manager |

## IP address plan

| Range | CIDR | Used for |
|---|---|---|
| Nodes | `10.0.0.0/20` | GKE node primary IPs |
| Pods | `10.4.0.0/14` | Pod alias IPs (secondary range) |
| Services | `10.8.0.0/20` | ClusterIP services (secondary range) |
| Master | `172.16.0.0/28` | GKE control plane (private endpoint) |

## Prerequisites

1. A GCP project with billing enabled.
2. The identity running Terraform must have `roles/owner` or `roles/editor` + `roles/resourcemanager.projectIamAdmin`.
3. A GCS bucket for remote state. Create it once:
   ```bash
   gcloud storage buckets create gs://gke-platform-tfstate-dev \
     --project=YOUR_PROJECT \
     --location=us-east1 \
     --uniform-bucket-level-access
   ```
4. `terraform >= 1.5`, `google` provider `>= 5.0`, `google-beta` provider `>= 5.0`.

## Backend configuration

[backend.tf](backend.tf) (or set via `-backend-config`):
```hcl
terraform {
  backend "gcs" {
    bucket = "gke-platform-tfstate-dev"
    prefix = "gcp/dev/terraform.tfstate"
  }
}
```

## Variables

Set these in `terraform.tfvars`:

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `project_id` | `string` | Yes | — | GCP project ID |
| `region` | `string` | No | `"us-east1"` | Region for all resources |
| `master_authorized_networks` | `list(object)` | No | `[]` | CIDRs allowed to reach the GKE API server; `[]` allows all (acceptable in dev) |

Example `terraform.tfvars`:
```hcl
project_id = "my-dev-project-123"
region     = "us-east1"

# Optional: lock down the GKE API server to your workstation/VPN
master_authorized_networks = [
  { cidr_block = "203.0.113.0/24", display_name = "office-vpn" }
]
```

## Deploy

```bash
cd gcp/environments/dev

terraform init
terraform plan -out=dev.tfplan
terraform apply dev.tfplan
```

Modules deploy in dependency order automatically:
`security` → `networking` → `gke`, `cloud_sql`, `cloud_storage`, `cloud_armor`, `artifact_registry`, `redis`

First apply takes ~15 minutes (GKE cluster provisioning dominates).

## Outputs

| Output | Sensitive | Description |
|---|---|---|
| `gke_cluster_name` | No | Cluster name (`gke-dev`) |
| `gke_cluster_endpoint` | Yes | GKE API server IP |
| `cloud_sql_instance` | Yes | `PROJECT:REGION:INSTANCE` — pass to Cloud SQL Auth Proxy |
| `cloud_sql_private_ip` | Yes | Private IP of the PostgreSQL primary |
| `storage_bucket` | No | GCS bucket name |
| `artifact_registry_url` | No | Base image URL: `us-east1-docker.pkg.dev/{project}/gke-dev-app` |
| `cloud_armor_policy` | No | Policy name — use in `BackendConfig` YAML |
| `redis_host` | Yes | Private IP of the Redis primary |
| `redis_port` | No | Redis port (`6379`) |
| `redis_auth_secret` | No | Secret Manager secret ID for the AUTH token |
| `redis_gsa_email` | No | GSA email to annotate the `redis-sa` KSA |
| `kubeconfig_command` | No | Full `gcloud` command to configure kubectl |

Print all outputs after apply:
```bash
terraform output
terraform output -raw kubeconfig_command | bash
```

## Post-apply checks

```bash
# 1. Connect kubectl to the cluster
$(terraform output -raw kubeconfig_command)

# 2. Verify nodes are Ready
kubectl get nodes

# 3. Check NAP is enabled
kubectl describe cluster gke-dev | grep -A5 "Cluster Autoscaling"

# 4. Verify Cloud SQL is reachable from within the VPC
gcloud sql instances describe gke-dev-pg --project=YOUR_PROJECT | grep ipAddress

# 5. Verify the Redis AUTH token is stored in Secret Manager
gcloud secrets versions access latest \
  --secret=$(terraform output -raw redis_auth_secret) \
  --project=YOUR_PROJECT

# 6. Push a test image
IMAGE="$(terraform output -raw artifact_registry_url)/test:latest"
docker pull nginx:alpine && docker tag nginx:alpine "$IMAGE"
gcloud auth configure-docker us-east1-docker.pkg.dev
docker push "$IMAGE"
```

## Destroy

```bash
terraform destroy
```

`force_destroy = true` on the Cloud Storage bucket means Terraform will empty and delete it. All other resources have `deletion_protection = false` so destroy completes without manual intervention.
