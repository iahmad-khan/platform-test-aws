# Module: cloud_sql

Creates a private Cloud SQL PostgreSQL 16 instance with automated backups, point-in-time recovery, query insights, and optional read replica. Authentication is IAM-based via the Cloud SQL Auth Proxy — no passwords are stored or needed.

## Resources created

- `google_sql_database_instance` — primary PostgreSQL 16 instance (private IP only)
- `google_sql_database_instance` (conditional) — read replica in the same or a different region
- `google_sql_database` — application database
- `google_sql_user` — IAM service account user (type `CLOUD_IAM_SERVICE_ACCOUNT`; no password)

## Variables

| Name | Type | Default | Description |
|---|---|---|---|
| `project_id` | `string` | — | GCP project ID |
| `region` | `string` | `"us-east1"` | Region for the primary instance |
| `name` | `string` | — | Prefix for instance names |
| `vpc_self_link` | `string` | — | VPC self-link from the networking module |
| `private_service_connection` | `string` | — | PSA connection ID from the networking module (dependency ordering) |
| `database_name` | `string` | `"appdb"` | Name of the database to create |
| `tier` | `string` | `"db-g1-small"` | Machine tier — e.g. `db-g1-small` (dev), `db-custom-2-7680` (prod) |
| `availability_type` | `string` | `"ZONAL"` | `ZONAL` (dev) or `REGIONAL` (prod HA with automatic failover) |
| `retained_backups` | `number` | `3` | Number of automated backups to keep (COUNT-based) |
| `transaction_log_retention_days` | `number` | `7` | Days to retain transaction logs for PITR |
| `deletion_protection` | `bool` | `false` | Prevent accidental instance deletion (`true` in prod) |
| `enable_read_replica` | `bool` | `false` | Create a read replica |
| `replica_tier` | `string` | `""` | Machine tier for the replica; defaults to the primary tier |
| `replica_region` | `string` | `""` | Region for the replica; defaults to the primary region |
| `cloud_sql_gsa_email` | `string` | — | GSA email from the security module; used as the IAM database user |
| `labels` | `map(string)` | `{}` | Labels applied to instances |

## Outputs

| Name | Sensitive | Description |
|---|---|---|
| `instance_name` | No | Primary instance name |
| `instance_connection_name` | Yes | `PROJECT:REGION:INSTANCE` — used by Cloud SQL Auth Proxy |
| `private_ip_address` | Yes | Private IP of the primary |
| `database_name` | No | Name of the created database |
| `replica_connection_name` | Yes | Auth Proxy connection name for the replica (`null` if no replica) |
| `replica_private_ip_address` | Yes | Private IP of the replica (`null` if no replica) |

## Usage

```hcl
module "cloud_sql" {
  source = "../../modules/cloud_sql"

  project_id                 = var.project_id
  region                     = var.region
  name                       = "gke-dev"
  vpc_self_link              = module.networking.vpc_self_link
  private_service_connection = module.networking.private_service_connection
  database_name              = "appdb"
  tier                       = "db-g1-small"
  availability_type          = "ZONAL"
  retained_backups           = 3
  deletion_protection        = false
  enable_read_replica        = false
  cloud_sql_gsa_email        = module.security.cloud_sql_gsa_email
  labels                     = { environment = "dev", managed_by = "terraform" }
}
```

## Connecting from GKE pods

Use the [Cloud SQL Auth Proxy](https://cloud.google.com/sql/docs/postgres/sql-proxy) as a sidecar. The pod's Kubernetes ServiceAccount must be annotated with the Cloud SQL GSA email (created by the `security` module):

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cloud-sql-sa
  namespace: apps
  annotations:
    iam.gke.io/gcp-service-account: <cloud_sql_gsa_email>
---
spec:
  serviceAccountName: cloud-sql-sa
  containers:
    - name: app
      env:
        - name: DB_HOST
          value: "127.0.0.1"
        - name: DB_PORT
          value: "5432"
    - name: cloud-sql-proxy
      image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:2
      args:
        - "--structured-logs"
        - "--port=5432"
        - "<instance_connection_name>"   # from terraform output
```

For read/write split in prod, add both connections:
```
- "PROJECT:REGION:gke-prod-pg?port=5432"         # primary
- "PROJECT:REGION:gke-prod-pg-replica?port=5433"  # replica
```

## Backup policy

- Automated backups run daily at 02:00
- **3 backups retained** (COUNT-based — not time-based)
- PITR logs retained for 7 days
- To restore: use `gcloud sql backups restore` or the Cloud Console

## Notes

- **`private_service_connection`** — passing `module.networking.private_service_connection` creates an implicit Terraform dependency ensuring the PSA VPC peering exists before Cloud SQL attempts to allocate a private IP.
- **IAM user name** — the user is created as `trimsuffix(gsa_email, ".gserviceaccount.com")` because Cloud SQL IAM users must not include the `.gserviceaccount.com` suffix.
- **Replica backups** — read replicas cannot have backups enabled; `backup_configuration.enabled = false` is set explicitly on the replica resource.
- **Deleting prod** — set `deletion_protection = false` and apply before `terraform destroy`. The instance will also need `skip_final_snapshot` if it was set to require one.
