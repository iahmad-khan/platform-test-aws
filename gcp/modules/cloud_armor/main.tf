# Google Cloud Armor security policy attached to the HTTPS Load Balancer that
# fronts GKE ingress. To activate it, annotate each Kubernetes Service with a
# BackendConfig reference (see outputs.tf for the exact YAML to apply).
#
# Protection layers:
#   1. Adaptive Protection — ML-based Layer 7 DDoS detection and mitigation
#   2. OWASP Core Rule Set — WAF rules for SQLi, XSS, LFI, RCE, scanners
#   3. Rate limiting — throttle IPs exceeding the configured request rate
#   4. IP allowlist / denylist — optional explicit CIDR rules

resource "google_compute_security_policy" "policy" {
  provider = google-beta

  project     = var.project_id
  name        = "${var.name}-armor"
  description = "Cloud Armor policy for ${var.name}: DDoS + WAF + rate limiting"

  # Adaptive Protection: ML model monitors traffic and auto-suggests/enforces
  # rules when a volumetric L7 DDoS attack is detected.
  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable          = true
      rule_visibility = "STANDARD"
    }
  }

  # ── Priority 100: explicit IP denylist ────────────────────────────────────

  dynamic "rule" {
    for_each = length(var.denied_ip_ranges) > 0 ? [1] : []
    content {
      action      = "deny(403)"
      priority    = 100
      description = "Block explicitly denylisted CIDRs"

      match {
        versioned_expr = "SRC_IPS_V1"
        config {
          src_ip_ranges = var.denied_ip_ranges
        }
      }
    }
  }

  # ── Priority 200: explicit IP allowlist ───────────────────────────────────

  dynamic "rule" {
    for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      action      = "allow"
      priority    = 200
      description = "Always allow trusted CIDRs (bypass WAF and rate limiting)"

      match {
        versioned_expr = "SRC_IPS_V1"
        config {
          src_ip_ranges = var.allowed_ip_ranges
        }
      }
    }
  }

  # ── Priority 1000–1004: OWASP WAF rules ───────────────────────────────────
  # evaluatePreconfiguredExpr uses Cloud Armor's managed rule sets (CRS 3.3).
  # Sensitivity levels: lower = fewer false positives, higher = stricter.

  rule {
    action      = "deny(403)"
    priority    = 1000
    description = "OWASP CRS: SQL injection protection"

    match {
      expr {
        expression = "evaluatePreconfiguredExpr('sqli-stable', {'sensitivity': 1})"
      }
    }
  }

  rule {
    action      = "deny(403)"
    priority    = 1001
    description = "OWASP CRS: Cross-site scripting protection"

    match {
      expr {
        expression = "evaluatePreconfiguredExpr('xss-stable', {'sensitivity': 1})"
      }
    }
  }

  rule {
    action      = "deny(403)"
    priority    = 1002
    description = "OWASP CRS: Local file inclusion protection"

    match {
      expr {
        expression = "evaluatePreconfiguredExpr('lfi-stable', {'sensitivity': 1})"
      }
    }
  }

  rule {
    action      = "deny(403)"
    priority    = 1003
    description = "OWASP CRS: Remote code execution protection"

    match {
      expr {
        expression = "evaluatePreconfiguredExpr('rce-stable', {'sensitivity': 1})"
      }
    }
  }

  rule {
    action      = "deny(403)"
    priority    = 1004
    description = "OWASP CRS: Scanner detection (blocks automated scanners)"

    match {
      expr {
        expression = "evaluatePreconfiguredExpr('scannerdetection-stable', {'sensitivity': 1})"
      }
    }
  }

  # ── Priority 2000: per-IP rate limiting ───────────────────────────────────
  # Throttle individual IPs exceeding the threshold; excess requests get 429.

  rule {
    action      = "throttle"
    priority    = 2000
    description = "Rate limit: ${var.rate_limit_count} req/${var.rate_limit_interval_sec}s per IP"

    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }

    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"

      rate_limit_threshold {
        count        = var.rate_limit_count
        interval_sec = var.rate_limit_interval_sec
      }
    }
  }

  # ── Priority 2147483647: default allow ────────────────────────────────────

  rule {
    action      = "allow"
    priority    = 2147483647
    description = "Default allow — traffic that passed all rules above"

    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }
}
