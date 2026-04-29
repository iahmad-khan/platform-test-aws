# GCP Platform — Terraform Stack

Production-grade GKE infrastructure on Google Cloud, managed with Terraform. Mirrors the AWS EKS stack in `../aws/` using GCP-native equivalents.

---

## Architecture Overview

```
Internet
   │  HTTPS (443)
   ▼
Google Cloud Armor           ← WAF + DDoS + rate limiting
   │
   ▼
HTTPS Load Balancer          ← GKE HTTP LB addon (auto-created by Ingress)
   │
   ▼
GKE Ingress → Services → Pods
   │
   ├── Node Auto Provisioning → x86 nodes (e2, n2, c2)
   │                         → ARM64 nodes (t2a, on arm64 node selector)
   │                         → GPU nodes  (T4 / A100 / L4, on nvidia.com/gpu request)
   │
   ├── Workload Identity → Cloud SQL (Auth Proxy, no passwords)
   └── Workload Identity → Cloud Storage (object read/write)

Artifact Registry ← GKE node SA pulls images without imagePullSecrets
```

---

## Module Reference

| Module | Purpose |
|---|---|
| [networking](modules/networking/) | VPC, node subnet + pod/service secondary ranges, Cloud NAT, Private Service Access, firewall rules |
| [security](modules/security/) | GCP API enablement, GKE node SA, Cloud SQL GSA, Cloud Storage GSA, Workload Identity bindings |
| [gke](modules/gke/) | Private GKE cluster, Node Auto Provisioning (CPU/RAM/GPU/ARM64), Dataplane V2, Workload Identity, system node pool |
| [cloud_sql](modules/cloud_sql/) | PostgreSQL 16, private IP, PITR backups (retain 3), read replica, IAM DB auth |
| [cloud_storage](modules/cloud_storage/) | Versioned GCS bucket, public access prevented, Workload Identity IAM binding |
| [cloud_armor](modules/cloud_armor/) | Cloud Armor security policy: Adaptive DDoS, OWASP WAF, rate limiting, IP allowlist/denylist |
| [artifact_registry](modules/artifact_registry/) | Docker repository, node SA reader access for passwordless image pulls |

---

## Prerequisites

### Tools
```bash
# Required versions
terraform >= 1.10
gcloud    >= 460.0.0

# Install gcloud: https://cloud.google.com/sdk/docs/install
gcloud components install kubectl
```

### GCP project setup
```bash
# Authenticate
gcloud auth application-default login

# Set default project (replace with your project ID)
gcloud config set project YOUR_PROJECT_ID

# Pre-create the Terraform state bucket (one per environment)
gsutil mb -p YOUR_PROJECT_ID -l us-east1 gs://gke-platform-tfstate-dev
gsutil mb -p YOUR_PROJECT_ID -l us-east1 gs://gke-platform-tfstate-prod

# Enable versioning on state buckets
gsutil versioning set on gs://gke-platform-tfstate-dev
gsutil versioning set on gs://gke-platform-tfstate-prod
```

The `security` module enables all required GCP APIs automatically on the first `terraform apply`. No manual API enablement is needed.

---

## Deploying an Environment

### 1. Configure variables

Edit `environments/dev/terraform.tfvars`:
```hcl
project_id = "my-dev-project-12345"
region     = "us-east1"

master_authorized_networks = [
  {
    cidr_block   = "203.0.113.0/24"   # your office/VPN CIDR
    display_name = "office-vpn"
  }
]
```

### 2. Initialize Terraform
```bash
cd environments/dev
terraform init
```

### 3. Preview changes
```bash
terraform plan -out=tfplan
```

### 4. Apply
```bash
terraform apply tfplan
```

> **Note on first apply:** The `security` module enables GCP APIs which can take ~2 minutes. Terraform automatically retries dependent resources. If you hit a timing error, re-run `terraform apply`.

### 5. Connect kubectl
```bash
# Copy the output command and run it:
terraform output -raw kubeconfig_command | bash
kubectl get nodes
```

---

## Environment Differences

| Setting | dev | prod |
|---|---|---|
| GKE release channel | REGULAR | STABLE |
| System node pool size | 1 × e2-standard-2 | 3 × e2-standard-4 |
| NAP CPU max | 1000 vCPU | 1000 vCPU |
| NAP RAM max | 1024 GiB | 1024 GiB |
| NAP GPU T4 max | 4 | 16 |
| NAP GPU A100 max | 0 | 8 |
| NAP GPU L4 max | 4 | 16 |
| Binary Authorization | disabled | enforced |
| deletion_protection | false | true |
| Cloud SQL tier | db-g1-small | db-custom-2-7680 |
| Cloud SQL HA | ZONAL | REGIONAL |
| Cloud SQL read replica | disabled | enabled |
| Backup retention | 3 backups | 3 backups |
| Armor rate limit | 500 req/min | 200 req/min |
| master_authorized_networks | 0.0.0.0/0 | VPN CIDR only |

---

## Key Features

### Node Auto Provisioning (NAP)

NAP automatically creates and deletes node pools to match workload demands. No manual node pool management is required.

**Limits (cluster-wide):**
- CPU: up to 1000 vCPUs
- RAM: up to 1024 GiB (~1 TB)
- NVIDIA T4 GPU: up to 16 (dev: 4)
- NVIDIA A100 GPU: up to 8 (dev: 0)
- NVIDIA L4 GPU: up to 16 (dev: 4)

**ARM64 workloads (Tau T2A machines):**

NAP automatically provisions ARM64-compatible nodes when pods request them:
```yaml
spec:
  nodeSelector:
    kubernetes.io/arch: arm64
```

**GPU workloads:**

NAP provisions GPU nodes when pods request GPU resources. GKE automatically installs NVIDIA drivers via a managed DaemonSet:
```yaml
spec:
  containers:
    - resources:
        limits:
          nvidia.com/gpu: 1
  nodeSelector:
    cloud.google.com/gke-accelerator: nvidia-tesla-t4   # or nvidia-l4, nvidia-tesla-a100
```

### Workload Identity

Pods access Cloud SQL and Cloud Storage using their Google Service Account identity — no static credentials or Kubernetes Secrets required.

**Setup for Cloud SQL access:**
```yaml
# 1. Create the Kubernetes ServiceAccount (must match the name in terraform.tfvars)
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cloud-sql-sa          # matches var.cloud_sql_ksa_name
  namespace: apps             # matches var.gke_namespace
  annotations:
    iam.gke.io/gcp-service-account: gke-dev-cloud-sql@PROJECT_ID.iam.gserviceaccount.com
```

```yaml
# 2. Use the ServiceAccount in your Deployment with the Cloud SQL Auth Proxy sidecar
spec:
  serviceAccountName: cloud-sql-sa
  containers:
    - name: cloud-sql-proxy
      image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:2
      args:
        - "--structured-logs"
        - "--port=5432"
        - "PROJECT_ID:us-east1:gke-dev-pg"  # from terraform output cloud_sql_instance
```

**Setup for Cloud Storage access:**
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cloud-storage-sa      # matches var.cloud_storage_ksa_name
  namespace: apps
  annotations:
    iam.gke.io/gcp-service-account: gke-dev-cloud-storage@PROJECT_ID.iam.gserviceaccount.com
```

Get the GSA email addresses:
```bash
terraform output -json | jq '{sql: .cloud_sql_instance, bucket: .storage_bucket}'
# GSA emails follow the pattern: <name>-cloud-sql@<project>.iam.gserviceaccount.com
```

### Cloud Armor + GKE Ingress

Cloud Armor is attached at the HTTP Load Balancer level via GKE's `BackendConfig` CRD.

**1. Get the policy name from Terraform output:**
```bash
terraform output cloud_armor_policy
# e.g. gke-dev-armor
```

**2. Create a BackendConfig in each namespace:**
```yaml
# backendconfig.yaml
apiVersion: cloud.google.com/v1
kind: BackendConfig
metadata:
  name: cloud-armor-config
  namespace: apps
spec:
  securityPolicy:
    name: gke-dev-armor    # from terraform output above
```
```bash
kubectl apply -f backendconfig.yaml
```

**3. Annotate each Service:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app
  namespace: apps
  annotations:
    cloud.google.com/backend-config: '{"default": "cloud-armor-config"}'
spec:
  type: NodePort              # required for GKE Ingress + Cloud Armor
  ports:
    - port: 80
      targetPort: 8080
```

**4. Verify in the GCP console:**
Navigate to **Network Security → Cloud Armor → Policies → gke-dev-armor** to see traffic stats and adaptive protection alerts.

### Artifact Registry — Passwordless Image Pulls

The GKE node service account is granted `artifactregistry.reader` on the repository. All pods on the cluster can pull images without configuring `imagePullSecrets`.

```bash
# Get the registry URL
terraform output artifact_registry_url
# e.g. us-east1-docker.pkg.dev/my-project/gke-dev-app

# Authenticate Docker (once per workstation / CI runner)
gcloud auth configure-docker us-east1-docker.pkg.dev

# Build and push
docker build -t us-east1-docker.pkg.dev/my-project/gke-dev-app/my-service:v1.0.0 .
docker push us-east1-docker.pkg.dev/my-project/gke-dev-app/my-service:v1.0.0
```

```yaml
# Use the image in a Deployment — no imagePullSecrets needed
spec:
  containers:
    - name: my-service
      image: us-east1-docker.pkg.dev/my-project/gke-dev-app/my-service:v1.0.0
```

### Cloud SQL — Read Replica

The prod environment creates a read replica. Applications connect to:
- **Primary** (read-write): use `cloud_sql_instance` output → Cloud SQL Auth Proxy port 5432
- **Replica** (read-only): use `cloud_sql_replica_connection_name` output → Auth Proxy port 5433

```yaml
# Sidecar with both primary and replica
- name: cloud-sql-proxy
  image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:2
  args:
    - "PROJECT:us-east1:gke-prod-pg?port=5432"        # primary (read-write)
    - "PROJECT:us-east1:gke-prod-pg-replica?port=5433" # replica (read-only)
```

---

## Testing

### Terraform validation (no GCP credentials needed)
```bash
cd environments/dev
terraform init -backend=false
terraform validate
```

### Full plan dry-run
```bash
cd environments/dev
terraform init
terraform plan -var="project_id=my-dev-project"
```

### Post-apply checks

```bash
# 1. Cluster is reachable
kubectl cluster-info

# 2. System node pool is healthy
kubectl get nodes -l node-pool=system

# 3. NAP is active
kubectl describe cm cluster-autoscaler-status -n kube-system | grep -A5 "NodeAutoProvisioner"

# 4. Workload Identity is working
# Deploy a test pod that calls the metadata server
kubectl run wi-test --image=google/cloud-sdk:slim --rm -it -- \
  gcloud auth print-identity-token

# 5. Image pull from Artifact Registry (no imagePullSecrets)
kubectl run ar-test \
  --image=us-east1-docker.pkg.dev/MY_PROJECT/gke-dev-app/my-service:v1.0.0 \
  --restart=Never -- sleep 60
kubectl get pod ar-test   # should reach Running without ImagePullBackOff

# 6. Cloud Armor policy is attached (after applying BackendConfig)
gcloud compute security-policies describe gke-dev-armor --format="table(rules[].action,rules[].priority)"

# 7. Cloud SQL private IP is accessible from within the cluster
kubectl run psql-test --image=postgres:16 --rm -it -- \
  psql "host=PRIVATE_IP dbname=appdb sslmode=disable"
```

### GPU scheduling test
```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test
spec:
  nodeSelector:
    cloud.google.com/gke-accelerator: nvidia-tesla-t4
  containers:
    - name: cuda
      image: nvidia/cuda:12.0-base
      command: ["nvidia-smi"]
      resources:
        limits:
          nvidia.com/gpu: 1
  restartPolicy: Never
EOF

kubectl wait pod/gpu-test --for=condition=Ready --timeout=300s
kubectl logs gpu-test   # should show GPU device info
kubectl delete pod gpu-test
```

### ARM64 scheduling test
```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: arm64-test
spec:
  nodeSelector:
    kubernetes.io/arch: arm64
  containers:
    - name: busybox
      image: busybox
      command: ["uname", "-m"]
  restartPolicy: Never
EOF

kubectl wait pod/arm64-test --for=condition=Ready --timeout=300s
kubectl logs arm64-test   # should print: aarch64
kubectl delete pod arm64-test
```

---

## Destroying an Environment

```bash
cd environments/dev
terraform destroy
```

> **Prod:** `deletion_protection = true` on both GKE and Cloud SQL blocks destruction. Set it to `false` first, apply, then destroy.
> ```bash
> terraform apply -var="project_id=..." # after editing deletion_protection to false in main.tf
> terraform destroy
> ```

---

## Deploying to a New Project

Each environment is completely isolated by `project_id`. To deploy a new environment (e.g. `staging`):

1. Copy `environments/dev/` to `environments/staging/`
2. Update `terraform.tfvars` with the new project ID
3. Update `backend.tf` with a unique GCS bucket name
4. Create the state bucket: `gsutil mb gs://gke-platform-tfstate-staging`
5. Adjust sizing variables in `main.tf` as needed
6. Run `terraform init && terraform apply`

---

## Costs (approximate, us-east1)

| Resource | dev/month | prod/month |
|---|---|---|
| GKE cluster fee | $73 | $73 |
| System nodes (e2-standard-2 × 1) | ~$50 | ~$300 (e2-std-4 × 3) |
| Cloud SQL (db-g1-small) | ~$26 | ~$200+ (db-custom-2-7680) |
| Cloud SQL replica | — | ~$100+ |
| Cloud NAT | ~$5 | ~$5+ |
| Cloud Armor (Standard) | ~$5/policy | ~$5/policy |
| Artifact Registry | ~$0.10/GB | ~$0.10/GB |
| NAP nodes | pay-as-you-go | pay-as-you-go |

Costs scale with NAP-provisioned nodes. Set budget alerts in GCP Billing.
