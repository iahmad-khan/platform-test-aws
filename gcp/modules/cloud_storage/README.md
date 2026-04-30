# Module: cloud_storage

Creates a private, versioned Google Cloud Storage bucket with uniform bucket-level access, enforced public access prevention, lifecycle rules, and a Workload Identity IAM binding so GKE pods can read and write objects without static credentials.

## Resources created

- `google_storage_bucket` — the GCS bucket
- `google_storage_bucket_iam_member` — grants `storage.objectAdmin` to the Cloud Storage GSA

## Variables

| Name | Type | Default | Description |
|---|---|---|---|
| `project_id` | `string` | — | GCP project ID |
| `name` | `string` | — | Suffix appended to `project_id` to form the globally unique bucket name |
| `location` | `string` | `"US-EAST1"` | GCS location — use a region (`US-EAST1`) or multi-region (`US`) |
| `force_destroy` | `bool` | `false` | Allow Terraform to delete the bucket even when it contains objects (set `true` in dev only) |
| `log_expiry_days` | `number` | `90` | Delete all object versions after this many days |
| `cloud_storage_gsa_email` | `string` | — | GSA email from the security module; granted `storage.objectAdmin` |
| `labels` | `map(string)` | `{}` | Labels applied to the bucket |

## Outputs

| Name | Sensitive | Description |
|---|---|---|
| `bucket_name` | No | Globally unique bucket name (`{project_id}-{name}`) |
| `bucket_url` | No | `gs://` URL for use with `gsutil` and client libraries |

## Usage

```hcl
module "cloud_storage" {
  source = "../../modules/cloud_storage"

  project_id              = var.project_id
  name                    = "gke-dev-assets"
  location                = "US-EAST1"
  force_destroy           = true       # dev only
  log_expiry_days         = 30
  cloud_storage_gsa_email = module.security.cloud_storage_gsa_email
  labels                  = { environment = "dev", managed_by = "terraform" }
}
```

## Connecting from GKE pods

Annotate the Kubernetes ServiceAccount with the Cloud Storage GSA email (created by the `security` module):

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cloud-storage-sa
  namespace: apps
  annotations:
    iam.gke.io/gcp-service-account: <cloud_storage_gsa_email>
```

Application code uses the GCP SDK — credentials are injected automatically via Workload Identity:

```python
from google.cloud import storage

client = storage.Client()
bucket = client.bucket(os.environ["BUCKET_NAME"])

# Upload
bucket.blob("path/to/file").upload_from_filename("local_file.txt")

# Download
bucket.blob("path/to/file").download_to_filename("local_file.txt")
```

## Lifecycle policy

Two rules are applied:

| Rule | Condition | Action |
|---|---|---|
| Version pruning | More than 3 non-current versions exist | Delete oldest non-current versions |
| Age expiry | Object age exceeds `log_expiry_days` | Delete |

## Notes

- **Bucket name** is `{project_id}-{name}`. The project ID prefix ensures global uniqueness without requiring a random suffix.
- **`public_access_prevention = "enforced"`** — blocks all public access even if an IAM binding granting `allUsers` or `allAuthenticatedUsers` is added. This cannot be overridden at the object level.
- **`force_destroy = true`** in dev means `terraform destroy` will empty and delete the bucket. In prod this is `false` — Terraform will refuse to delete a non-empty bucket, protecting against accidental data loss.
- **GSA permission** — `storage.objectAdmin` allows the GSA to create, read, update, and delete objects. If your workload only needs read access, consider changing this to `roles/storage.objectViewer` in the IAM binding.
