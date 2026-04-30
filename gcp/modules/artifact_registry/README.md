# Module: artifact_registry

Creates an Artifact Registry Docker repository and grants the GKE node service account read access so all pods on the cluster can pull images without `imagePullSecrets`. Optionally grants a CI/CD service account write access for pushing images.

## Resources created

- `google_artifact_registry_repository` — Docker format repository
- `google_artifact_registry_repository_iam_member` — node SA `roles/artifactregistry.reader`
- `google_artifact_registry_repository_iam_member` (conditional) — CI/CD SA `roles/artifactregistry.writer`

## Variables

| Name | Type | Default | Description |
|---|---|---|---|
| `project_id` | `string` | — | GCP project ID |
| `region` | `string` | `"us-east1"` | Region for the repository |
| `repository_id` | `string` | — | Repository name — part of the image URL |
| `node_service_account_email` | `string` | — | GKE node SA email from the security module; granted `artifactregistry.reader` |
| `cicd_service_account_email` | `string` | `""` | Optional CI/CD SA email; granted `artifactregistry.writer` when set |
| `labels` | `map(string)` | `{}` | Labels applied to the repository |

## Outputs

| Name | Sensitive | Description |
|---|---|---|
| `repository_id` | No | Repository ID |
| `repository_url` | No | Base image URL: `{region}-docker.pkg.dev/{project}/{repository_id}` — append `/{image}:{tag}` |

## Usage

```hcl
module "artifact_registry" {
  source = "../../modules/artifact_registry"

  project_id                 = var.project_id
  region                     = var.region
  repository_id              = "gke-dev-app"
  node_service_account_email = module.security.node_service_account_email
  cicd_service_account_email = ""    # set to a SA email to enable CI/CD push access
  labels                     = { environment = "dev", managed_by = "terraform" }
}
```

## Pushing images

```bash
# Authenticate Docker (once per workstation / CI runner)
gcloud auth configure-docker us-east1-docker.pkg.dev

# Build and push
IMAGE="us-east1-docker.pkg.dev/MY_PROJECT/gke-dev-app/my-service:v1.0.0"
docker build -t "$IMAGE" .
docker push "$IMAGE"
```

## Pulling images in GKE (no imagePullSecrets needed)

The GKE kubelet uses the node service account to authenticate image pulls from Artifact Registry. No `imagePullSecrets` or additional configuration is required in pod specs:

```yaml
spec:
  containers:
    - name: my-service
      image: us-east1-docker.pkg.dev/MY_PROJECT/gke-dev-app/my-service:v1.0.0
```

This works for all pods on the cluster, regardless of their Kubernetes ServiceAccount, because authentication happens at the kubelet (node) level.

## How passwordless pulls work

```
kubelet pulls image
  └─ uses node SA credentials (node_service_account_email)
       └─ node SA has roles/artifactregistry.reader on this repository
            └─ pull succeeds without imagePullSecrets
```

The `security` module also grants `artifactregistry.reader` at the project level so NAP-provisioned node pools automatically inherit the same access.

## Notes

- **Repository per environment** — dev uses `gke-dev-app`, prod uses `gke-prod-app`. This provides isolation: a misconfigured prod deploy cannot accidentally pull a dev image.
- **CI/CD write access** — set `cicd_service_account_email` to a dedicated CI/CD SA (not the node SA). Keeping push and pull credentials separate limits blast radius if either is compromised.
- **Image URL** — `terraform output artifact_registry_url` prints the base URL. Tag images as `{base_url}/{image}:{tag}`.
- **Multi-repo** — call this module multiple times with different `repository_id` values if you need separate repos per service or team.
