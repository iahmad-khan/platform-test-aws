# GCP Platform Architecture

A production-grade GKE platform stack managed by Terraform. Eight reusable modules compose into two environment configurations (dev and prod) inside a single GCP project per environment.

---

## Repository layout

```
gcp/
├── arch.md                     ← this file
├── modules/
│   ├── security/               # APIs + IAM: must run first
│   ├── networking/             # VPC, subnets, NAT, PSA peering
│   ├── gke/                    # GKE cluster + system node pool + NAP
│   ├── cloud_sql/              # PostgreSQL 16 primary + optional read replica
│   ├── cloud_storage/          # Private GCS bucket
│   ├── cloud_armor/            # Layer 7 WAF + DDoS + rate limiting
│   ├── artifact_registry/      # Docker registry with passwordless pulls
│   └── redis/                  # Memorystore Redis + Secret Manager + WI
└── environments/
    ├── dev/                    # Small, fast-destroy, REGULAR channel
    └── prod/                   # HA, deletion-protected, STABLE channel
```

---

## Full architecture diagram

```
 ┌────────────────────────────────────────────────────────────────────────────────┐
 │                              Internet / Clients                                │
 └──────────────────────────────────────┬─────────────────────────────────────────┘
                                        │ HTTPS
                                        ▼
 ┌──────────────────────────────────────────────────────────────────────────────┐
 │                           Cloud Armor (WAF)                                  │
 │  ① denylist (priority 100)   ② allowlist (priority 200)                     │
 │  ③ OWASP CRS: SQLi, XSS, LFI, RCE, scanner (priority 1000-1004)            │
 │  ④ per-IP rate limit / throttle (priority 2000)                              │
 │  ⑤ Adaptive Protection — ML-based L7 DDoS detection (always on)             │
 └──────────────────────────────────────┬───────────────────────────────────────┘
                                        │ allowed traffic
                                        ▼
 ┌──────────────────────────────────────────────────────────────────────────────┐
 │                     GCP HTTPS Load Balancer (GKE Ingress)                    │
 │              BackendConfig annotation links policy to each Service            │
 └──────────────────────────────────────┬───────────────────────────────────────┘
                                        │
                                        ▼
 ╔══════════════════════════════════════════════════════════════════════════════╗
 ║            GKE Cluster  "gke-{env}-cluster"  (Regional — multi-zone)        ║
 ║            location = us-east1   node_locations = [b, c, d]  (prod)         ║
 ║   Release channel: REGULAR (dev)  /  STABLE (prod)                           ║
 ║   Upgrade strategy: BLUE_GREEN — new nodes provisioned before old drained    ║
 ║                                                                              ║
 ║  ┌─────────────────────────────┐   ┌────────────────────────────────────┐   ║
 ║  │    System Node Pool         │   │  Node Auto Provisioning (NAP)      │   ║
 ║  │  "gke-{env}-system"        │   │  (automatic — no manual mgmt)      │   ║
 ║  │                             │   │                                    │   ║
 ║  │  Taint: node-pool=system    │   │  ┌─────────┐ ┌────────┐ ┌──────┐  │   ║
 ║  │  NoSchedule                 │   │  │  x86    │ │ ARM64  │ │ GPU  │  │   ║
 ║  │  Runs: kube-system only     │   │  │ pools   │ │ (T2A)  │ │ pools│  │   ║
 ║  │                             │   │  │         │ │        │ │T4/L4/│  │   ║
 ║  │  dev:  1×e2-standard-2×2z   │   │  │         │ │ arch=  │ │A100  │  │   ║
 ║  │  prod: 3×e2-standard-4×3z   │   │  │ default │ │ arm64  │ │      │  │   ║
 ║  └─────────────────────────────┘   │  │         │ │        │ │nvidia│  │   ║
 ║                                    │  └─────────┘ └────────┘ │.com/ │  │   ║
 ║  Limits: 1000 vCPU  /  1024 GiB   │                          │ gpu  │  │   ║
 ║          16 T4  /  8 A100 / 16 L4  └──────────────────────────┴──────┘  ─   ║
 ║                                                                              ║
 ║  Dataplane V2 (eBPF / Cilium)   Workload Identity   Managed Prometheus       ║
 ║  Private nodes (no external IPs)   Binary AuthZ (prod)   Shielded VMs        ║
 ╚════════════╤══════════════════╤═══════════════════╤════════════════╤═════════╝
              │                  │                   │                │
   Cloud SQL  │       Redis      │    Cloud Storage  │  Artifact Reg. │ (image pull)
   Auth Proxy │    (Workload     │    (Workload      │                │
   sidecar    │     Identity)    │     Identity)     │                │
              │                  │                   │                │
              ▼                  ▼                   ▼                ▼
 ┌────────────────────────────────────────────────────────────────────────────┐
 │                        Custom VPC  "gke-{env}-vpc"                         │
 │                                                                            │
 │  ┌─────────────────────────────────────────────────────────────────────┐   │
 │  │              Node Subnet  "gke-{env}-nodes"                         │   │
 │  │                                                                     │   │
 │  │  Primary range   (nodes):    10.0.0.0/20  (dev)  10.10.0.0/20 (prod)│  │
 │  │  Secondary range (pods):     10.4.0.0/14  (dev)  10.16.0.0/14 (prod)│  │
 │  │  Secondary range (services): 10.8.0.0/20  (dev)  10.20.0.0/20 (prod)│  │
 │  │                                                                     │   │
 │  │  VPC Flow Logs: 5-sec interval, 50% sampling                        │   │
 │  │  Private Google Access: enabled (reach GCP APIs without NAT)        │   │
 │  └─────────────────────────────────────────────────────────────────────┘   │
 │                                                                            │
 │  ┌─────────────────────┐   ┌────────────────────────────────────────────┐  │
 │  │  Cloud Router + NAT │   │    Private Service Access (PSA) peering    │  │
 │  │  AUTO ephemeral IPs │   │    Reserved /16 block → servicenetworking  │  │
 │  │  Egress for nodes   │   │    Shared by Cloud SQL + Redis             │  │
 │  └─────────────────────┘   └────────────────────────────────────────────┘  │
 │                                                                            │
 │  Firewall rules:                                                           │
 │    allow-internal  — nodes/pods/services talk to each other (TCP/UDP/ICMP) │
 │    allow-master    — control plane → kubelet (10250), webhook (8443)        │
 │    allow-hc        — GCP LB health checks (35.191/16, 130.211/22)          │
 └─────────────┬───────────────────────┬──────────────────────────────────────┘
               │ PSA peering           │ PSA peering
               ▼                       ▼
 ┌─────────────────────────┐   ┌──────────────────────────┐
 │  Cloud SQL (PostgreSQL) │   │  Memorystore Redis        │
 │  "gke-{env}-pg"         │   │  "gke-{env}-redis"        │
 │                         │   │                           │
 │  Private IP (PSA)       │   │  Private IP (PSA)         │
 │  No public IP           │   │  No public IP             │
 │  IAM auth (no password) │   │  AUTH token → Secret Mgr  │
 │  Auth Proxy sidecar     │   │  TLS: SERVER_AUTH (prod)  │
 │                         │   │                           │
 │  dev:  ZONAL, 1 primary │   │  dev:  BASIC, 1 GiB       │
 │  prod: REGIONAL HA      │   │  prod: STANDARD_HA, 4 GiB │
 │        + read replica   │   │        + 1 read replica   │
 │  Backups: last 3, PITR  │   │  Maintenance: Sun 03:00   │
 └─────────────────────────┘   └──────────────────────────┘

 ┌──────────────────────────┐   ┌──────────────────────────┐
 │  Cloud Storage (GCS)     │   │  Artifact Registry        │
 │  "{project}-gke-{env}-   │   │  "gke-{env}-app"          │
 │   assets"                │   │                           │
 │                          │   │  Docker format            │
 │  Private, versioned      │   │  Node SA → reader         │
 │  Uniform bucket-level ACL│   │  No imagePullSecrets      │
 │  dev:  30-day expiry     │   │  CI/CD SA → writer (prod) │
 │  prod: 365-day expiry    │   │                           │
 │  Workload Identity access│   │  us-east1-docker.pkg.dev/ │
 └──────────────────────────┘   └──────────────────────────┘
```

---

## Request flow (client → pod)

```
Client
  │
  │ HTTPS (443)
  ▼
Cloud Armor  ──► denylist hit?  ──► 403
  │
  │ passed all rules
  ▼
GCP HTTPS Load Balancer
  │
  │  BackendConfig on each Kubernetes Service sets the armor policy name
  ▼
GKE Ingress (nginx / GKE Ingress controller)
  │
  ├─► Service A  ──► Pod(s) on NAP x86 pool
  ├─► Service B  ──► Pod(s) on NAP ARM64 pool
  └─► Service C  ──► Pod(s) on NAP GPU pool

Pod makes outbound requests to:
  ├─► Cloud SQL via Cloud SQL Auth Proxy sidecar (unix socket, IAM auth)
  ├─► Redis via private IP:6379 (AUTH token from Secret Manager)
  └─► Cloud Storage via GCS client library (Workload Identity ADC)
```

---

## Workload Identity flow

No static credentials exist anywhere in the cluster. Every service-to-GCP interaction is identity-based:

```
┌───────────────────────────────────────────────────────────────┐
│  Pod spec                                                     │
│    serviceAccountName: cloud-sql-sa    ← Kubernetes SA (KSA) │
└───────────────────────────────────────────────────────────────┘
          │
          │  KSA annotated with:
          │  iam.gke.io/gcp-service-account: gke-dev-cloud-sql@PROJECT.iam.gserviceaccount.com
          │
          ▼
┌───────────────────────────────────────────────────────────────┐
│  GKE Workload Identity                                        │
│  KSA  ──►  GSA  via  roles/iam.workloadIdentityUser          │
│  Binding: PROJECT.svc.id.goog[NAMESPACE/KSA_NAME]            │
└───────────────────────────────────────────────────────────────┘
          │
          │  Pod's OIDC token exchanged for GSA access token (transparent)
          │
          ├──► Cloud SQL GSA  (roles/cloudsql.client)
          │       └─► Cloud SQL Auth Proxy authenticates as GSA → IAM DB login
          │
          ├──► Cloud Storage GSA  (roles/storage.objectViewer / objectAdmin)
          │       └─► GCS client library uses ADC automatically
          │
          └──► Redis GSA  (secretmanager.secretAccessor)
                  └─► Fetch AUTH token from Secret Manager at pod startup
                       └─► redis.Redis(host=..., password=token)
```

There are three GSAs (Google Service Accounts):
| GSA | Purpose | Permissions |
|---|---|---|
| `{name}-gke-node` | Kubelet / node-level ops | logging, monitoring, artifactregistry.reader, storage.objectViewer |
| `{name}-cloud-sql` | Cloud SQL access | `roles/cloudsql.client` → IAM DB user |
| `{name}-cloud-storage` | GCS access | bound to `cloud-storage-sa` KSA; bucket IAM grants object permissions |
| `{name}-redis` | Secret Manager (AUTH token) | `secretmanager.secretAccessor` on the Redis AUTH secret |

---

## Networking topology

```
                 VPC  "gke-{env}-vpc"
                       │
          ┌────────────┴────────────┐
          │                         │
   Node subnet                   PSA reserved /16
   (primary + 2 secondary ranges)   │
          │                   servicenetworking peering
   ┌──────┴──────┐                  │
   │   Nodes     │           ┌──────┴──────────────────┐
   │ 10.0.0/20   │           │  Google-managed network  │
   ├─────────────┤           │  Cloud SQL primary IP    │
   │   Pods      │           │  Cloud SQL replica IP    │
   │ 10.4.0/14   │           │  Redis primary IP        │
   ├─────────────┤           │  Redis read endpoint IP  │
   │  Services   │           └──────────────────────────┘
   │ 10.8.0/20   │
   └─────────────┘
          │
   Cloud Router + NAT
   (outbound egress for nodes
    pulling images, calling APIs)

Control plane: 172.16.0.0/28  (dev)  172.16.1.0/28  (prod)
  Separate /28 per env — safe to peer both envs with no CIDR overlap.
```

Private Service Access (PSA) is a VPC peering from Google's managed infrastructure into your VPC. Cloud SQL and Memorystore both live in Google-managed VMs; their private IPs are routable from GKE pods directly — no proxies or extra hops at the network layer. The `google_service_networking_connection` established in the networking module is shared by both services.

---

## Module dependency order

```
security          ← always first: enables 9 GCP APIs, creates all GSAs
    │
    ▼
networking        ← VPC, subnet, NAT, PSA peering
    │
    ├──► gke              (needs VPC + subnet + node SA)
    ├──► cloud_sql        (needs VPC self-link + PSA connection)
    ├──► cloud_storage    (needs Cloud Storage GSA)
    ├──► cloud_armor      (no network deps; references project only)
    ├──► artifact_registry(needs node SA for reader binding)
    └──► redis            (needs VPC ID + PSA connection)
```

Terraform resolves this automatically by tracking output-to-input references. The only explicit `depends_on` is `module.networking → module.security` (APIs must exist before VPC resources are created).

---

## Blue-green node upgrades

Both the system node pool and all NAP-provisioned pools use the `BLUE_GREEN` upgrade strategy. During a GKE version upgrade, GKE provisions new nodes before draining old ones — zero-downtime by design.

```
Upgrade cycle (prod — 20% batches):

  [old nodes ×10]
       │
       ▼  batch 1: provision 2 new nodes, drain 2 old nodes, wait 120s
  [old ×8 | new ×2]
       │
       ▼  batch 2: provision 2 more, drain 2 old, wait 120s
  [old ×6 | new ×4]
       │  ... 3 more batches ...
       ▼
  [new nodes ×10]  ──► 300s final soak ──► upgrade complete
```

| Setting | dev | prod |
|---|---|---|
| `batch_percentage` | 50% | 20% |
| `batch_soak_duration` | 60 s | 120 s |
| `node_pool_soak_duration` | 120 s | 300 s |

---

## Multi-zone distribution

Setting `location = var.region` creates a **regional cluster**. The control plane is replicated across 3 GCP zones automatically. Node placement is controlled with `node_locations`:

```
                    us-east1 (region)
                   ┌────────────────────────────────────┐
                   │  zone-b   │  zone-c   │  zone-d    │
                   │           │           │            │
  Control plane    │  replica  │  replica  │  primary   │  ← managed by GCP
                   │           │           │            │
  System pool      │  3 nodes  │  3 nodes  │  3 nodes   │  ← prod (9 total)
  (prod)           │           │           │            │
                   │           │           │            │
  NAP pools        │  auto     │  auto     │  auto      │  ← provisioned on demand
  (all envs)       │  scale    │  scale    │  scale     │
                   └───────────┴───────────┴────────────┘

Dev: node_locations = [zone-b, zone-c]  → 2-zone footprint, lower cost
     system_node_count = 1 × 2 zones = 2 system nodes
```

---

## Environment comparison

| Aspect | dev | prod |
|---|---|---|
| GKE release channel | REGULAR | STABLE |
| System node count | 1 × e2-standard-2 × 2 zones | 3 × e2-standard-4 × 3 zones |
| Blue-green batch | 50%, 60 s soak | 20%, 120 s soak |
| Binary Authorization | disabled | enforced |
| GKE deletion_protection | false | true |
| Cloud SQL tier | db-g1-small | db-custom-2-7680 |
| Cloud SQL HA | ZONAL | REGIONAL (auto-failover) |
| Cloud SQL read replica | no | yes (db-custom-2-3840) |
| Cloud SQL deletion_protection | false | true |
| Cloud Storage force_destroy | true | false |
| Cloud Storage expiry | 30 days | 365 days |
| Cloud Armor rate limit | 500 req / 60 s | 200 req / 60 s |
| Cloud Armor IP allowlist | none | `trusted_ip_ranges` variable |
| Artifact Registry CI/CD push | none | `cicd_service_account_email` variable |
| Redis tier | BASIC (no failover) | STANDARD_HA (auto-failover) |
| Redis memory | 1 GiB | 4 GiB |
| Redis TLS | DISABLED | SERVER_AUTHENTICATION |
| Redis read replica | no | 1 replica |

---

## Security posture summary

| Layer | Control |
|---|---|
| Edge | Cloud Armor: OWASP WAF + DDoS adaptive protection + per-IP rate limit |
| Node | Shielded VMs: Secure Boot + integrity monitoring; COS Containerd image |
| Cluster | Private nodes (no external IPs); Dataplane V2 (eBPF); Workload Identity |
| Identity | No static credentials — pods use short-lived OIDC tokens exchanged for GSA tokens |
| Images | Artifact Registry; Binary Authorization enforced in prod (signed images only) |
| Database | Cloud SQL private IP only; IAM-based auth (no passwords); PITR backups |
| Cache | Redis AUTH token stored in Secret Manager; TLS in prod |
| Storage | Uniform bucket-level ACL; no public access; versioning enabled |
| Secrets | Zero Kubernetes Secrets for service credentials — Secret Manager + Workload Identity |
| Audit | Cloud Logging: system + workload components; VPC Flow Logs; SQL query insights |
