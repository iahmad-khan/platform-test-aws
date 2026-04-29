output "security_policy_name" {
  value       = google_compute_security_policy.policy.name
  description = "Reference this in a Kubernetes BackendConfig to attach Cloud Armor to GKE ingress"
}

output "security_policy_self_link" {
  value = google_compute_security_policy.policy.self_link
}

# ── How to wire Cloud Armor to GKE ingress ────────────────────────────────────
#
# 1. Create a BackendConfig in each namespace that needs protection:
#
#    apiVersion: cloud.google.com/v1
#    kind: BackendConfig
#    metadata:
#      name: cloud-armor-config
#      namespace: apps
#    spec:
#      securityPolicy:
#        name: "<security_policy_name>"   # use the output above
#
# 2. Annotate every Service that the Ingress routes to:
#
#    apiVersion: v1
#    kind: Service
#    metadata:
#      annotations:
#        cloud.google.com/backend-config: '{"default": "cloud-armor-config"}'
#
# 3. The GKE HTTP Load Balancing controller automatically attaches the Cloud
#    Armor policy to the backend service it creates for each annotated Service.
#
# Apply with: kubectl apply -f backendconfig.yaml
