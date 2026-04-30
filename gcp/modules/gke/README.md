# Module: gke

Creates a private, VPC-native GKE Standard cluster with Node Auto Provisioning (NAP), Workload Identity, Dataplane V2, and a dedicated system node pool. NAP automatically provisions x86, ARM64, and GPU node pools on demand.

## Resources created

- `google_container_cluster` (google-beta provider) — the GKE cluster with all security and networking configuration
- `google_container_node_pool` — system node pool for `kube-system` workloads (tainted; NAP handles all application pools)

## Variables

| Name | Type | Default | Description |
|---|---|---|---|
| `project_id` | `string` | — | GCP project ID |
| `region` | `string` | `"us-east1"` | Region (cluster is regional, not zonal) |
| `name` | `string` | — | Prefix for cluster and node pool names |
| `network_self_link` | `string` | — | VPC self-link from the networking module |
| `subnetwork_self_link` | `string` | — | Node subnet self-link from the networking module |
| `pods_range_name` | `string` | — | Secondary range name for pods |
| `services_range_name` | `string` | — | Secondary range name for ClusterIP services |
| `master_ipv4_cidr` | `string` | `"172.16.0.0/28"` | `/28` for control-plane VPC peering; must match networking module |
| `node_service_account_email` | `string` | — | GKE node SA email from the security module |
| `master_authorized_networks` | `list(object)` | `[]` | CIDRs allowed to reach the public API server |
| `enable_binary_authorization` | `bool` | `false` | Enforce signed images (`true` in prod) |
| `deletion_protection` | `bool` | `true` | Prevent accidental cluster deletion |
| `release_channel` | `string` | `"REGULAR"` | `RAPID` / `REGULAR` / `STABLE` |
| `system_node_count` | `number` | `1` | Nodes in the system pool (use `3` in prod for HA) |
| `system_node_machine_type` | `string` | `"e2-standard-4"` | Machine type for system nodes |
| `cpu_min` | `number` | `4` | Minimum cluster-wide vCPUs for NAP |
| `cpu_max` | `number` | `1000` | Maximum cluster-wide vCPUs NAP may provision |
| `memory_min` | `number` | `16` | Minimum cluster-wide GiB for NAP |
| `memory_max` | `number` | `1024` | Maximum cluster-wide GiB NAP may provision (~1 TB) |
| `gpu_t4_max` | `number` | `16` | Max NVIDIA T4 GPUs; set `0` to disable T4 nodes |
| `gpu_a100_max` | `number` | `8` | Max NVIDIA A100 GPUs; set `0` to disable A100 nodes |
| `gpu_l4_max` | `number` | `16` | Max NVIDIA L4 GPUs; set `0` to disable L4 nodes |
| `maintenance_start_time` | `string` | `"2025-01-01T00:00:00Z"` | Start of the weekly maintenance window |
| `maintenance_end_time` | `string` | `"2025-01-01T06:00:00Z"` | End of the weekly maintenance window |
| `labels` | `map(string)` | `{}` | Resource labels applied to the cluster |

## Outputs

| Name | Sensitive | Description |
|---|---|---|
| `cluster_name` | No | Cluster name — used in `gcloud container clusters get-credentials` |
| `cluster_endpoint` | Yes | API server IP address |
| `cluster_ca_certificate` | Yes | Base64-encoded cluster CA certificate |
| `cluster_id` | No | Full resource ID of the cluster |

## Usage

```hcl
module "gke" {
  source = "../../modules/gke"

  project_id                 = var.project_id
  region                     = var.region
  name                       = "gke-dev"
  network_self_link          = module.networking.vpc_self_link
  subnetwork_self_link       = module.networking.subnet_self_link
  pods_range_name            = module.networking.pods_range_name
  services_range_name        = module.networking.services_range_name
  node_service_account_email = module.security.node_service_account_email

  master_authorized_networks = [
    { cidr_block = "203.0.113.0/24", display_name = "office-vpn" }
  ]

  release_channel             = "REGULAR"
  deletion_protection         = false
  system_node_count           = 1
  system_node_machine_type    = "e2-standard-2"
  cpu_max                     = 1000
  memory_max                  = 1024
  gpu_t4_max                  = 4
  gpu_a100_max                = 0
  gpu_l4_max                  = 4
  enable_binary_authorization = false
  labels                      = { environment = "dev", managed_by = "terraform" }
}
```

## VPC-native networking

The cluster is VPC-native (alias IP mode) because `ip_allocation_policy` is set with named secondary ranges. This is required for private clusters and enables direct pod-to-pod routing without NAT.

## Node Auto Provisioning (NAP)

NAP creates and deletes node pools automatically based on pending pod requests. You never manage application node pools directly.

**ARM64 workloads** — NAP provisions Tau T2A (ARM) nodes when pods include:
```yaml
spec:
  nodeSelector:
    kubernetes.io/arch: arm64
```

**GPU workloads** — NAP provisions GPU nodes when pods request:
```yaml
spec:
  containers:
    - resources:
        limits:
          nvidia.com/gpu: 1
  nodeSelector:
    cloud.google.com/gke-accelerator: nvidia-tesla-t4  # or nvidia-l4, nvidia-tesla-a100
```
GKE automatically installs the NVIDIA driver on GPU nodes via a managed DaemonSet — no manual driver configuration required.

## System node pool

The system pool runs only `kube-system` workloads (CoreDNS, kube-proxy, metrics-server, etc.) because it carries a `NoSchedule` taint:
```
key=node-pool, value=system, effect=NoSchedule
```
Application pods must either tolerate this taint or rely on NAP to provision an untainted pool.

## Notes

- **google-beta provider** — required for `security_posture_config` and some NAP fields. Both `google` and `google-beta` providers must be configured in the calling environment.
- **Dataplane V2** — uses eBPF (Cilium) instead of kube-proxy. `network_policy.enabled` must be `false` when `datapath_provider = "ADVANCED_DATAPATH"`.
- **Binary Authorization** — when `enable_binary_authorization = true`, only images signed by your attestors can be deployed. You must configure attestors and policies separately before enabling this in production.
- **Deleting a prod cluster** — set `deletion_protection = false` and apply before running `terraform destroy`.
