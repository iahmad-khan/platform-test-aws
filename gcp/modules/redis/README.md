# Module: redis

Creates a Memorystore for Redis instance (Google-managed Redis) with AUTH enabled, stores the GCP-generated AUTH token in Secret Manager, and wires Workload Identity so GKE pods can retrieve the token at runtime without static Kubernetes Secrets.

## Resources created

- `google_project_service` × 2 — enables `redis.googleapis.com` and `secretmanager.googleapis.com`
- `terraform_data` — anchors the PSA peering dependency at the resource level
- `google_redis_instance` — Memorystore Redis (BASIC or STANDARD_HA)
- `google_secret_manager_secret` — stores the GCP-generated AUTH token
- `google_secret_manager_secret_version` — initial version with the token value
- `google_service_account` — Redis Workload Identity GSA
- `google_secret_manager_secret_iam_member` — grants GSA `secretmanager.secretAccessor` on the AUTH secret
- `google_service_account_iam_member` — Workload Identity binding: KSA → GSA

## Variables

| Name | Type | Default | Description |
|---|---|---|---|
| `project_id` | `string` | — | GCP project ID |
| `region` | `string` | `"us-east1"` | Region for the Redis instance |
| `name` | `string` | — | Prefix for all resource names |
| `vpc_id` | `string` | — | VPC resource ID (`projects/.../global/networks/...`) from the networking module |
| `private_service_connection` | `string` | — | PSA connection ID from the networking module (enforces creation order) |
| `tier` | `string` | `"BASIC"` | `BASIC` (no failover) or `STANDARD_HA` (auto-failover replica) |
| `memory_size_gb` | `number` | `1` | Redis memory in GiB |
| `redis_version` | `string` | `"REDIS_7_0"` | `REDIS_6_X` or `REDIS_7_0` |
| `enable_read_replica` | `bool` | `false` | Enable read replicas (only valid with `STANDARD_HA`) |
| `replica_count` | `number` | `1` | Number of read replicas (1–5); only used when `enable_read_replica = true` |
| `transit_encryption_mode` | `string` | `"DISABLED"` | `DISABLED` (VPC isolation only) or `SERVER_AUTHENTICATION` (TLS) |
| `gke_namespace` | `string` | `"apps"` | Kubernetes namespace of the bound ServiceAccount |
| `redis_ksa_name` | `string` | `"redis-sa"` | Name of the Kubernetes ServiceAccount that impersonates the Redis GSA |
| `labels` | `map(string)` | `{}` | Labels applied to all resources |

## Outputs

| Name | Sensitive | Description |
|---|---|---|
| `host` | Yes | Private IP of the Redis primary — reachable only within the VPC |
| `port` | No | Redis port (default `6379`) |
| `read_endpoint` | Yes | Private IP of the read endpoint (populated only when `enable_read_replica = true`) |
| `read_endpoint_port` | No | Port of the read endpoint |
| `auth_secret_id` | No | Secret Manager secret ID for the AUTH token |
| `auth_secret_version` | Yes | Full resource name of the latest secret version |
| `redis_gsa_email` | No | GSA email — use as the `iam.gke.io/gcp-service-account` annotation value |

## Usage

```hcl
module "redis" {
  source = "../../modules/redis"

  project_id                 = var.project_id
  region                     = var.region
  name                       = "gke-dev"
  vpc_id                     = module.networking.vpc_id
  private_service_connection = module.networking.private_service_connection
  tier                       = "BASIC"
  memory_size_gb             = 1
  redis_version              = "REDIS_7_0"
  enable_read_replica        = false
  transit_encryption_mode    = "DISABLED"
  gke_namespace              = "apps"
  redis_ksa_name             = "redis-sa"
  labels                     = { environment = "dev", managed_by = "terraform" }
}
```

## Networking

Memorystore always runs in Google-managed infrastructure. With `connect_mode = "PRIVATE_SERVICE_ACCESS"`, GCP creates a VPC peering from its managed network to your VPC using the same PSA peering that Cloud SQL uses. From a GKE pod's perspective, the Redis private IP is directly routable — no proxies or additional hops.

```
GKE pod (10.4.x.x)
  └─ routes to Redis private IP via PSA peering (transparent)
       └─ Memorystore instance (Google-managed network)
```

## Workload Identity flow

```
Pod (redis-sa KSA, namespace: apps)
  └─ Workload Identity → Redis GSA
       └─ secretmanager.secretAccessor
            └─ Secret Manager: {name}-redis-auth
                 └─ returns GCP-generated AUTH token
                      └─ redis.Redis(host=..., password=token)
```

**Step 1 — create the Kubernetes ServiceAccount:**
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: redis-sa          # matches redis_ksa_name
  namespace: apps         # matches gke_namespace
  annotations:
    iam.gke.io/gcp-service-account: <redis_gsa_email>  # from terraform output
```

**Step 2 — fetch the AUTH token in your application:**

```python
# Python
from google.cloud import secretmanager
import redis, os

sm = secretmanager.SecretManagerServiceClient()
resp = sm.access_secret_version(
    name=f"projects/{os.environ['GCP_PROJECT']}/secrets/{os.environ['REDIS_AUTH_SECRET']}/versions/latest"
)
auth = resp.payload.data.decode("utf-8")
r = redis.Redis(host=os.environ["REDIS_HOST"], port=6379, password=auth, decode_responses=True)
```

```go
// Go
smc, _ := secretmanager.NewClient(ctx)
resp, _ := smc.AccessSecretVersion(ctx, &smpb.AccessSecretVersionRequest{
    Name: fmt.Sprintf("projects/%s/secrets/%s/versions/latest",
        os.Getenv("GCP_PROJECT"), os.Getenv("REDIS_AUTH_SECRET")),
})
rdb := goredis.NewClient(&goredis.Options{
    Addr:     os.Getenv("REDIS_HOST") + ":6379",
    Password: string(resp.Payload.Data),
})
```

## TLS (prod only)

When `transit_encryption_mode = "SERVER_AUTHENTICATION"`, clients must present the Redis server CA certificate:

```bash
# Retrieve the server CA cert after apply
gcloud redis instances describe gke-prod-redis \
  --region=us-east1 \
  --format="value(serverCaCerts[0].cert)" > redis-ca.pem
```

```python
import ssl
tls_ctx = ssl.create_default_context(cafile="redis-ca.pem")
r = redis.Redis(host=REDIS_HOST, port=6379, password=auth,
                ssl=True, ssl_ca_certs="redis-ca.pem")
```

## Notes

- **`private_service_connection` ordering** — the `terraform_data.psa_ready` resource holds this value, creating an explicit resource-level dependency that ensures the PSA peering is established before Memorystore allocates its private IP.
- **Read replicas require `STANDARD_HA`** — setting `enable_read_replica = true` with `tier = "BASIC"` will be silently ignored (replica_count is forced to 0).
- **AUTH token rotation** — GCP does not automatically rotate the Memorystore AUTH token. If you need to rotate, use `gcloud redis instances update --remove-redis-config requirepass` and regenerate, then update the Secret Manager version manually.
- **Maintenance window** — set to Sunday 03:00 to avoid peak hours. Memorystore STANDARD_HA instances failover to the replica during maintenance with no data loss.
