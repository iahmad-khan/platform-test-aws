output "host" {
  value       = google_redis_instance.cache.host
  sensitive   = true
  description = "Private IP address of the Redis primary; only reachable from within the VPC"
}

output "port" {
  value       = google_redis_instance.cache.port
  description = "Redis port (default 6379)"
}

output "read_endpoint" {
  value       = google_redis_instance.cache.read_endpoint
  sensitive   = true
  description = "Private IP of the read endpoint (populated only when enable_read_replica = true)"
}

output "read_endpoint_port" {
  value       = google_redis_instance.cache.read_endpoint_port
  description = "Port of the read endpoint"
}

output "auth_secret_id" {
  value       = google_secret_manager_secret.redis_auth.secret_id
  description = "Secret Manager secret ID containing the Redis AUTH token"
}

output "auth_secret_version" {
  value       = google_secret_manager_secret_version.redis_auth.name
  sensitive   = true
  description = "Full resource name of the latest secret version"
}

output "redis_gsa_email" {
  value       = google_service_account.redis.email
  description = "Annotate your Kubernetes ServiceAccount with: iam.gke.io/gcp-service-account=<this value>"
}

# ── How to use Redis from a GKE pod ───────────────────────────────────────────
#
# 1. Create a Kubernetes ServiceAccount with the Workload Identity annotation:
#
#    apiVersion: v1
#    kind: ServiceAccount
#    metadata:
#      name: redis-sa                 # matches var.redis_ksa_name
#      namespace: apps                # matches var.gke_namespace
#      annotations:
#        iam.gke.io/gcp-service-account: <redis_gsa_email>
#
# 2. In your application, fetch the AUTH token at startup using the GCP SDK:
#
#    Python example:
#      from google.cloud import secretmanager
#      client = secretmanager.SecretManagerServiceClient()
#      secret = client.access_secret_version(
#          name="projects/PROJECT_ID/secrets/<auth_secret_id>/versions/latest"
#      )
#      auth_token = secret.payload.data.decode("utf-8")
#      r = redis.Redis(host=REDIS_HOST, port=6379, password=auth_token)
#
#    Go example (with go-redis):
#      smc, _ := secretmanager.NewClient(ctx)
#      resp, _ := smc.AccessSecretVersion(ctx, &smpb.AccessSecretVersionRequest{
#          Name: "projects/PROJECT_ID/secrets/<auth_secret_id>/versions/latest",
#      })
#      rdb := goredis.NewClient(&goredis.Options{
#          Addr:     REDIS_HOST + ":6379",
#          Password: string(resp.Payload.Data),
#      })
#
# 3. If transit_encryption_mode = "SERVER_AUTHENTICATION", also configure TLS:
#    - Retrieve the server CA cert:
#      gcloud redis instances describe INSTANCE --region=REGION --format="value(serverCaCerts[0].cert)"
#    - Pass it as a TLS CA cert in your Redis client configuration.
