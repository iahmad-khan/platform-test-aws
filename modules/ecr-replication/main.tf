# Registry-level replication configuration — applies to the entire ECR registry
# in this account. Replicates all matching repos to the destination account/region.
#
# Place this in the SOURCE environment (staging).
# The DESTINATION environment (prod) must have an aws_ecr_registry_policy
# granting this account permission to push replicated images.

resource "aws_ecr_replication_configuration" "this" {
  replication_configuration {
    rule {
      destination {
        region      = var.destination_region
        registry_id = var.destination_account_id
      }

      # Empty prefix = replicate every repository in this registry.
      # Set repo_prefix_filter to scope it down (e.g. "clickhouse" or "platform/").
      # PREFIX_MATCH with "" replicates every repository in the registry.
      # Set repo_prefix_filter to a non-empty string to scope down (e.g. "clickhouse").
      repository_filter {
        filter      = var.repo_prefix_filter
        filter_type = "PREFIX_MATCH"
      }
    }
  }
}
