# EKS Terraform

Production-grade AWS infrastructure managed with Terraform. Covers EKS (Auto Mode), VPC, RDS Aurora Serverless v2, S3, CloudFront, Route53, ECR, and supporting identity and security resources — organized into reusable modules consumed by dev, staging, and prod environments across three separate AWS accounts.

## Architecture

```
environments/
├── dev/        # 10.10.0.0/16 — single NAT GW, 1 RDS instance, mutable ECR
├── staging/    # 10.20.0.0/16 — single NAT GW, 2 RDS instances, ECR → prod replication
└── prod/       # 10.30.0.0/16 — 3 NAT GWs (HA), 3 RDS instances, Shield Advanced

modules/
├── vpc/              VPC, subnets, NAT GWs, route tables, flow logs
├── security-groups/  ALB, EKS cluster/node, RDS, and VPC endpoint SGs
├── vpc-endpoints/    Interface endpoints for ECR (api, dkr) and STS
├── iam/              EKS cluster and node IAM roles
├── eks/              EKS Auto Mode cluster, Pod Identity addon, LBC/EBS CSI/External DNS IAM, Helm releases
├── rds/              Aurora PostgreSQL Serverless v2, KMS encryption, Secrets Manager
├── s3/               App and logs S3 buckets with lifecycle, CORS, and OAC policy
├── cloudfront/       CloudFront distribution with S3 OAC and ALB origins
├── route53/          Hosted zone lookup, ACM certs (us-east-1 + regional), DNS records
├── ecr/              ECR repository with lifecycle policy and optional cross-account pull policy
├── ecr-replication/  Registry-level replication rule (staging → prod)
├── pod-identity/     IAM role + S3/Translate policies + EKS Pod Identity association
├── demo-app/         Kubernetes deployment exposing /health, /s3, /translate endpoints
└── shield/           AWS Shield Advanced subscription + protections + protection group
```

### Key design decisions

- **EKS Auto Mode** — compute, storage, and load balancing managed by AWS; no managed node groups or Karpenter operator required. A custom `NodePool` CRD applies the `tenantname: amd-hosts` label.
- **Pod Identity only** — all pod-level AWS access uses EKS Pod Identity (`pods.eks.amazonaws.com` trust). No OIDC provider or IRSA annotations.
- **ECR without imagePullSecrets** — VPC interface endpoints for ECR and STS allow the EKS node credential provider to authenticate transparently from private subnets.
- **S3 native state locking** — `use_lockfile = true` (Terraform ≥ 1.10). No DynamoDB table required.

## Prerequisites

| Tool | Minimum version |
|------|----------------|
| Terraform | 1.10 |
| AWS CLI | 2.x |
| kubectl | matches cluster version |
| helm | 3.x |

AWS provider version constraints: `~> 5.80` (EKS Auto Mode requires ≥ 5.70).

## Repository layout

```
eks-terraform/
├── modules/         14 reusable modules (each: main.tf, variables.tf, outputs.tf)
├── environments/
│   ├── dev/         backend.tf  versions.tf  main.tf  variables.tf  outputs.tf  terraform.tfvars
│   ├── staging/     (same)
│   └── prod/        (same)
└── .gitignore
```

## Getting started

### 1. Configure tfvars

Each environment has a `terraform.tfvars`. At minimum update:

```hcl
domain_name = "yourdomain.com"   # must have an existing Route53 hosted zone
aws_region  = "us-east-1"
```

Cross-account IDs (used for ECR access policies and replication):

```hcl
# dev/terraform.tfvars
staging_account_id = "222222222222"

# staging/terraform.tfvars
dev_account_id  = "111111111111"
prod_account_id = "333333333333"

# prod/terraform.tfvars
staging_account_id = "222222222222"
```

### 2. Create state buckets

Each environment uses its own S3 bucket for state. Create them before running `terraform init`:

```bash
aws s3 mb s3://platform-terraform-state-<ACCOUNT_ID>-us-east-1 --region us-east-1
aws s3api put-bucket-versioning \
  --bucket platform-terraform-state-<ACCOUNT_ID>-us-east-1 \
  --versioning-configuration Status=Enabled
```

Update `backend.tf` in each environment with the correct bucket name.

### 3. Deploy

```bash
cd environments/dev    # or staging / prod

terraform init
terraform plan
terraform apply
```

Deploy in order: **dev → staging → prod**. Staging needs dev's ECR repo ARNs for the CI promoter policy; prod needs the staging account ID for the ECR registry replication policy.

## Post-apply

### Connect to the cluster

```bash
aws eks update-kubeconfig --region us-east-1 --name platform-<env>
kubectl get nodes
```

Nodes appear within ~2 minutes as Auto Mode provisions them on first workload.

### Verify the AWS Load Balancer Controller

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

### Retrieve the RDS password

```bash
aws secretsmanager get-secret-value \
  --secret-id $(terraform output -raw rds_master_secret_arn) \
  --query SecretString --output text | jq .
```

### Test the demo app (Pod Identity)

```bash
kubectl port-forward -n demo-app svc/demo-app 8080:8080

curl http://localhost:8080/health     # liveness check
curl http://localhost:8080/s3         # lists objects in the app S3 bucket
curl http://localhost:8080/translate  # translates a phrase via AWS Translate
```

## ECR image promotion workflow

```
CI pushes image → dev ECR
        ↓
CI script (staging IAM user) pulls from dev, pushes to staging ECR
        ↓
AWS ECR native replication → prod ECR (automatic, no CI involvement)
```

The staging CI user (`/ci/platform-ci-ecr-promoter`) is created in `environments/staging/main.tf`. Its access key is available as a sensitive Terraform output:

```bash
terraform -chdir=environments/staging output -raw ci_ecr_promoter_secret_access_key
```

## Environment comparison

| Parameter | dev | staging | prod |
|-----------|-----|---------|------|
| VPC CIDR | 10.10.0.0/16 | 10.20.0.0/16 | 10.30.0.0/16 |
| NAT Gateways | 1 | 1 | 3 (one per AZ) |
| RDS instances | 1 | 2 | 3 (1 writer + 2 readers) |
| Aurora ACU | 0.5–4 | 1–8 | 2–64 |
| Backup retention | 1 day | 3 days | 30 days |
| Deletion protection | false | false | true |
| CF price class | PriceClass\_100 | PriceClass\_100 | PriceClass\_All |
| Shield Advanced | — | — | enabled |
| ECR tag mutability | MUTABLE | IMMUTABLE | IMMUTABLE |

## AWS Shield Advanced (prod only)

> **Cost: $3,000/month per AWS organization**, billed from the moment `terraform apply` runs in prod. The subscription **cannot be cancelled via Terraform** — contact AWS Support to cancel.

Shield protects:
- CloudFront distribution
- Route53 hosted zone
- NAT Gateway EIPs (one per AZ)
- All ALBs created by the Load Balancer Controller (via `protection_group` with `pattern = "ALL"`)

The `aws_shield_subscription` resource has `prevent_destroy = true` to guard against accidental removal.

## Module inputs summary

### `modules/eks`

| Variable | Description |
|----------|-------------|
| `name` | Cluster name |
| `kubernetes_version` | Kubernetes version (default `1.31`) |
| `cluster_role_arn` | EKS control plane IAM role |
| `node_role_arn` | Auto Mode node IAM role |
| `private_subnet_ids` | Subnets for control plane ENIs and nodes |
| `cluster_sg_id` | Additional cluster security group |
| `node_sg_id` | Additional node security group |
| `route53_zone_arn` | Hosted zone ARN for External DNS IAM policy |
| `node_tenant_label` | Value for `tenantname` node label (default `amd-hosts`) |
| `enable_kube_prometheus` | Install kube-prometheus-stack (default `true`) |
| `enable_argocd` | Install ArgoCD (default `true`) |

### `modules/pod-identity`

| Variable | Description |
|----------|-------------|
| `name` | Name prefix for IAM resources |
| `cluster_name` | EKS cluster name for the Pod Identity association |
| `namespace` | Kubernetes namespace of the workload |
| `service_account_name` | Kubernetes service account name |
| `s3_bucket_arns` | List of S3 bucket ARNs the pod role can access |

## Helm chart versions

| Chart | Version |
|-------|---------|
| aws-load-balancer-controller | 1.8.3 |
| metrics-server | 3.12.1 |
| kube-prometheus-stack | 61.3.2 |
| argo-cd | 7.3.11 |

## Provider versions

```hcl
terraform  >= 1.10
aws        ~> 5.80
helm       ~> 2.12
kubernetes ~> 2.25
tls        ~> 4.0
```
