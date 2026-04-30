# Module: cloud_armor

Creates a Google Cloud Armor security policy that provides Layer 7 DDoS protection, OWASP WAF rules, and per-IP rate limiting for traffic entering the GKE cluster through the HTTPS Load Balancer. The policy is attached to individual GKE backend services via a Kubernetes `BackendConfig` resource.

## Resources created

- `google_compute_security_policy` (google-beta provider) — the security policy with all rules

## Security rules (in priority order)

| Priority | Action | Description |
|---|---|---|
| 100 | `deny(403)` | Explicit IP denylist (optional; configured via `denied_ip_ranges`) |
| 200 | `allow` | Explicit IP allowlist — bypass WAF and rate-limit (optional; configured via `allowed_ip_ranges`) |
| 1000 | `deny(403)` | OWASP CRS: SQL injection (`sqli-stable`, sensitivity 1) |
| 1001 | `deny(403)` | OWASP CRS: Cross-site scripting (`xss-stable`, sensitivity 1) |
| 1002 | `deny(403)` | OWASP CRS: Local file inclusion (`lfi-stable`, sensitivity 1) |
| 1003 | `deny(403)` | OWASP CRS: Remote code execution (`rce-stable`, sensitivity 1) |
| 1004 | `deny(403)` | OWASP CRS: Scanner detection (`scannerdetection-stable`, sensitivity 1) |
| 2000 | `throttle` | Per-IP rate limiting — exceed threshold → `429 Too Many Requests` |
| 2147483647 | `allow` | Default allow — traffic that passed all rules |

Adaptive Protection (ML-based Layer 7 DDoS detection) is always enabled.

## Variables

| Name | Type | Default | Description |
|---|---|---|---|
| `project_id` | `string` | — | GCP project ID |
| `name` | `string` | — | Prefix for the policy name |
| `allowed_ip_ranges` | `list(string)` | `[]` | CIDRs that skip WAF and rate-limiting (e.g. VPN, monitoring probes) |
| `denied_ip_ranges` | `list(string)` | `[]` | CIDRs blocked unconditionally before any other rule |
| `rate_limit_count` | `number` | `500` | Max requests per IP per `rate_limit_interval_sec` before throttling |
| `rate_limit_interval_sec` | `number` | `60` | Rolling window in seconds for the rate-limit threshold |
| `labels` | `map(string)` | `{}` | Labels applied to the policy |

## Outputs

| Name | Sensitive | Description |
|---|---|---|
| `security_policy_name` | No | Policy name — set this in the Kubernetes `BackendConfig` |
| `security_policy_self_link` | No | Full resource URL of the policy |

## Usage

```hcl
module "cloud_armor" {
  source = "../../modules/cloud_armor"

  project_id              = var.project_id
  name                    = "gke-dev"
  rate_limit_count        = 500
  rate_limit_interval_sec = 60
  allowed_ip_ranges       = ["10.0.0.0/8"]   # internal traffic skips WAF
  labels                  = { environment = "dev", managed_by = "terraform" }
}
```

## Attaching to GKE ingress

Cloud Armor operates at the HTTPS Load Balancer level. To attach the policy to a GKE service, create a `BackendConfig` and annotate the `Service`:

**Step 1 — create a BackendConfig** (apply once per namespace):
```yaml
apiVersion: cloud.google.com/v1
kind: BackendConfig
metadata:
  name: cloud-armor-config
  namespace: apps
spec:
  securityPolicy:
    name: gke-dev-armor    # from: terraform output cloud_armor_policy
```
```bash
kubectl apply -f backendconfig.yaml
```

**Step 2 — annotate each Service** that the Ingress routes to:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app
  namespace: apps
  annotations:
    cloud.google.com/backend-config: '{"default": "cloud-armor-config"}'
spec:
  type: NodePort     # required for GKE Ingress + Cloud Armor
  ports:
    - port: 80
      targetPort: 8080
```

**Verify** — after apply, check the policy in the GCP console:
```
Network Security → Cloud Armor → Policies → gke-dev-armor
```

## Notes

- **google-beta provider required** — the `adaptive_protection_config` and `rate_limit_options` blocks are in the beta provider. Both `google` and `google-beta` must be configured in the calling environment.
- **WAF sensitivity** — all OWASP rules use `sensitivity: 1` (lowest false-positive rate). Increase to 2 or 3 for stricter enforcement, but test thoroughly — higher sensitivity can block legitimate traffic.
- **Adaptive Protection** — ML model runs continuously. When an L7 DDoS attack is detected, Cloud Armor suggests or auto-enforces a mitigation rule. Review the Adaptive Protection dashboard regularly in prod.
- **Rate limits in prod** — the prod environment sets `rate_limit_count = 200` (vs 500 in dev). Adjust based on your expected legitimate traffic patterns per IP.
- **Cloud Armor Standard** — the WAF rules (`evaluatePreconfiguredExpr`) and rate limiting are included in Cloud Armor Standard (no additional license required). Threat Intelligence feeds require Cloud Armor Enterprise.
