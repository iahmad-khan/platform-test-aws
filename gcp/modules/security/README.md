# Module: security

Enables all required GCP APIs and creates the Google Service Accounts (GSAs) and Workload Identity bindings used by the rest of the stack. **This module must be applied first** — all other modules depend on the APIs it enables.

## Resources created

- `google_project_service` × 9 — enables: `container`, `sqladmin`, `storage`, `iam`, `servicenetworking`, `cloudresourcemanager`, `artifactregistry`, `redis`, `secretmanager`
- `google_service_account` — GKE node SA (used by kubelet and NAP-provisioned nodes)
- `google_project_iam_member` × 5 — node SA roles: `logging.logWriter`, `monitoring.metricWriter`, `monitoring.viewer`, `artifactregistry.reader`, `storage.objectViewer`
- `google_service_account` — Cloud SQL GSA (Workload Identity for database access)
- `google_project_iam_member` — `roles/cloudsql.client` for the Cloud SQL GSA
- `google_service_account_iam_member` — Workload Identity binding: Cloud SQL KSA → Cloud SQL GSA
- `google_service_account` — Cloud Storage GSA (Workload Identity for bucket access)
- `google_service_account_iam_member` — Workload Identity binding: Cloud Storage KSA → Cloud Storage GSA

## Variables

| Name | Type | Default | Description |
|---|---|---|---|
| `project_id` | `string` | — | GCP project ID |
| `name` | `string` | — | Prefix for service account IDs (e.g. `gke-dev`) |
| `gke_namespace` | `string` | `"apps"` | Kubernetes namespace where the bound ServiceAccounts live |
| `cloud_sql_ksa_name` | `string` | `"cloud-sql-sa"` | Name of the Kubernetes ServiceAccount that impersonates the Cloud SQL GSA |
| `cloud_storage_ksa_name` | `string` | `"cloud-storage-sa"` | Name of the Kubernetes ServiceAccount that impersonates the Cloud Storage GSA |
| `labels` | `map(string)` | `{}` | Labels applied to service accounts |

## Outputs

| Name | Sensitive | Description |
|---|---|---|
| `node_service_account_email` | No | Email of the GKE node SA — passed to `gke` and `artifact_registry` modules |
| `cloud_sql_gsa_email` | No | Email of the Cloud SQL GSA — passed to `cloud_sql` module and used to annotate the KSA |
| `cloud_storage_gsa_email` | No | Email of the Cloud Storage GSA — passed to `cloud_storage` module and used to annotate the KSA |

## Usage

```hcl
module "security" {
  source = "../../modules/security"

  project_id             = var.project_id
  name                   = "gke-dev"
  gke_namespace          = "apps"
  cloud_sql_ksa_name     = "cloud-sql-sa"
  cloud_storage_ksa_name = "cloud-storage-sa"
  labels                 = { environment = "dev", managed_by = "terraform" }
}
```

## Workload Identity

This module creates the **GCP side** of Workload Identity for Cloud SQL and Cloud Storage. You must also create the matching Kubernetes ServiceAccounts with the correct annotation:

```yaml
# Cloud SQL
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cloud-sql-sa          # matches cloud_sql_ksa_name
  namespace: apps             # matches gke_namespace
  annotations:
    iam.gke.io/gcp-service-account: <cloud_sql_gsa_email>

---
# Cloud Storage
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cloud-storage-sa      # matches cloud_storage_ksa_name
  namespace: apps
  annotations:
    iam.gke.io/gcp-service-account: <cloud_storage_gsa_email>
```

The `redis` module manages its own GSA and WI binding independently.

## Notes

- **API enablement timing** — enabling APIs is eventually consistent. On the very first apply, subsequent resources (especially `google_container_cluster`) may see a brief `API not enabled` error. Re-running `terraform apply` resolves this without any changes needed.
- **`disable_on_destroy = false`** — APIs are not disabled when this module is destroyed. Disabling APIs in a shared project can break other workloads.
- **Node SA scope** — the node SA is granted `artifactregistry.reader` at the project level so that NAP-provisioned node pools can pull images from any repository in the project without `imagePullSecrets`. The `artifact_registry` module additionally grants reader access at the repository level for defence-in-depth.
