# Module: networking

Creates the VPC and all network primitives required by every other module in this stack. Must be applied before `gke`, `cloud_sql`, and `redis`.

## Resources created

- `google_compute_network` — custom-mode VPC (no auto-created subnets)
- `google_compute_subnetwork` — node subnet with two secondary IP ranges (pods, services) and VPC Flow Logs enabled
- `google_compute_router` — regional Cloud Router for NAT
- `google_compute_router_nat` — Cloud NAT so private nodes can reach the internet (e.g. pulling images from external registries)
- `google_compute_global_address` — `/16` reserved block for Private Service Access
- `google_service_networking_connection` — PSA VPC peering used by Cloud SQL and Memorystore Redis
- `google_compute_firewall` × 3 — internal traffic, GKE control-plane → kubelets, Google health checks

## Variables

| Name | Type | Default | Description |
|---|---|---|---|
| `project_id` | `string` | — | GCP project ID |
| `region` | `string` | `"us-east1"` | Region for subnet, router, and NAT |
| `name` | `string` | — | Prefix for all resource names |
| `nodes_cidr` | `string` | `"10.0.0.0/20"` | Primary CIDR for GKE nodes |
| `pods_cidr` | `string` | `"10.4.0.0/14"` | Secondary range for pod IPs |
| `services_cidr` | `string` | `"10.8.0.0/20"` | Secondary range for ClusterIP services |
| `master_cidr` | `string` | `"172.16.0.0/28"` | `/28` block for the GKE control-plane peering; must not overlap any other range |
| `labels` | `map(string)` | `{}` | Labels applied to all resources |

## Outputs

| Name | Sensitive | Description |
|---|---|---|
| `vpc_self_link` | No | Full URL of the VPC — passed to GKE `network` |
| `vpc_id` | No | Resource ID (`projects/.../global/networks/...`) — required by Memorystore `authorized_network` |
| `subnet_self_link` | No | Full URL of the node subnet — passed to GKE `subnetwork` |
| `pods_range_name` | No | Secondary range name for pods — passed to GKE `ip_allocation_policy` |
| `services_range_name` | No | Secondary range name for services — passed to GKE `ip_allocation_policy` |
| `private_service_connection` | No | ID of the PSA peering — passed to `cloud_sql` and `redis` to enforce creation order |

## Usage

```hcl
module "networking" {
  source = "../../modules/networking"

  project_id    = var.project_id
  region        = var.region
  name          = "gke-dev"
  nodes_cidr    = "10.0.0.0/20"
  pods_cidr     = "10.4.0.0/14"
  services_cidr = "10.8.0.0/20"
  master_cidr   = "172.16.0.0/28"
  labels        = { environment = "dev", managed_by = "terraform" }

  depends_on = [module.security]  # ensures GCP APIs are enabled first
}
```

## Notes

- **CIDR planning** — the four ranges (`nodes_cidr`, `pods_cidr`, `services_cidr`, `master_cidr`) must not overlap each other or the PSA `/16` block that GCP allocates. When deploying multiple environments into the same project, use different ranges per environment (e.g. dev: `10.0.x`, prod: `10.10.x`).
- **PSA peering** — a single `google_service_networking_connection` covers both Cloud SQL and Memorystore. If you later add more PSA-based services (e.g. AlloyDB), they reuse the same peering automatically.
- **Cloud NAT** — uses `AUTO_ONLY` IP allocation (GCP manages the external IPs). Logs errors only to keep Cloud Logging costs low.
- **Firewall rules** — the `allow-master` rule permits TCP 443, 8443, and 10250 from `master_cidr` to nodes tagged `gke-node`. If you change `master_cidr`, update this variable consistently.
