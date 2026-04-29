data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ── Shield Advanced Subscription ──────────────────────────────────────────────
# WARNING: Enabling Shield Advanced commits the account to a 1-year contract
# at $3,000/month. It cannot be cancelled via Terraform — contact AWS Support.
# The lifecycle block prevents accidental destruction.
resource "aws_shield_subscription" "this" {
  auto_renew = "ENABLED"

  lifecycle {
    prevent_destroy = true
  }
}

# ── Resource Protections ───────────────────────────────────────────────────────

# CloudFront — absorbs volumetric attacks at the edge before they reach EKS
resource "aws_shield_protection" "cloudfront" {
  name         = "${var.name}-cloudfront"
  resource_arn = var.cloudfront_distribution_arn
  tags         = var.tags

  depends_on = [aws_shield_subscription.this]
}

# Route53 hosted zone — protects DNS from DNS-based DDoS
resource "aws_shield_protection" "route53" {
  name         = "${var.name}-route53"
  resource_arn = "arn:aws:route53:::hostedzone/${var.route53_zone_id}"
  tags         = var.tags

  depends_on = [aws_shield_subscription.this]
}

# NAT Gateway EIPs — protects outbound path; also covers inbound on those IPs
resource "aws_shield_protection" "nat_eip" {
  count        = length(var.nat_eip_arns)
  name         = "${var.name}-nat-eip-${count.index}"
  resource_arn = var.nat_eip_arns[count.index]
  tags         = var.tags

  depends_on = [aws_shield_subscription.this]
}

# ── Protection Group ───────────────────────────────────────────────────────────
# pattern = ALL automatically includes every Shield-eligible resource in the
# account (present and future), including ALBs created by the LBC.
# aggregation = MAX means the group is treated as attacked if any member is.
resource "aws_shield_protection_group" "all" {
  protection_group_id = "${var.name}-all-resources"
  aggregation         = "MAX"
  pattern             = "ALL"
  tags                = var.tags

  depends_on = [aws_shield_subscription.this]
}
