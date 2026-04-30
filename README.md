# cloud-terraform

Terraform infrastructure for two cloud platforms, organized as independent stacks under `aws/` and `gcp/`. Each stack has its own reusable modules and per-environment configurations.

```
cloud-terraform/
├── aws/        EKS platform — VPC, EKS Auto Mode, RDS Aurora, S3, CloudFront, Route53, ECR, Shield
└── gcp/        GKE platform — GKE Standard, Cloud SQL, Memorystore Redis, GCS, Cloud Armor, Artifact Registry
```

---

## AWS stack (`aws/`)

Production-grade EKS infrastructure across three AWS accounts (dev / staging / prod).

**Modules:** `vpc` · `security-groups` · `vpc-endpoints` · `iam` · `eks` · `rds` · `s3` · `cloudfront` · `route53` · `ecr` · `ecr-replication` · `pod-identity` · `shield` · `demo-app`

**Highlights:**
- EKS Auto Mode — no manual node group management
- Aurora PostgreSQL Serverless v2 with KMS encryption and Secrets Manager
- CloudFront + S3 OAC + ALB origins; Route53 ACM cert automation
- Pod Identity (replaces IRSA) for zero-static-credential workload access
- AWS Shield Advanced in prod with protection groups

See [aws/README.md](aws/README.md) for full documentation.

---

## GCP stack (`gcp/`)

Production-grade GKE platform across two GCP projects (dev / prod).

**Modules:** `security` · `networking` · `gke` · `cloud_sql` · `cloud_storage` · `cloud_armor` · `artifact_registry` · `redis`

**Highlights:**
- Regional GKE cluster (multi-zone) with Node Auto Provisioning for x86, ARM64, and GPU workloads
- Blue-green node upgrade strategy — zero-downtime version rollouts
- Workload Identity throughout — no static credentials in the cluster
- Cloud Armor WAF + OWASP CRS + adaptive DDoS protection at the edge
- Cloud SQL PostgreSQL 16 with REGIONAL HA and read replica (prod)
- Memorystore Redis with AUTH token in Secret Manager and TLS (prod)

See [gcp/arch.md](gcp/arch.md) for the full architecture diagram and component walkthrough.

---

## Prerequisites

| Stack | Requirement |
|---|---|
| Both | Terraform >= 1.5 |
| AWS | AWS CLI configured, provider `hashicorp/aws` >= 5.0 |
| GCP | `gcloud` authenticated, providers `google` + `google-beta` >= 5.0 |

## Deploying

Each environment is self-contained. Pick the one you want:

```bash
# AWS — dev
cd aws/environments/dev
terraform init && terraform apply

# GCP — prod
cd gcp/environments/prod
terraform init && terraform apply
```
