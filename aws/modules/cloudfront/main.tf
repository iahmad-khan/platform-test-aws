resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "${var.name}-s3-oac"
  description                       = "OAC for ${var.name} S3 app assets bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.name} CDN"
  aliases             = var.domain_aliases
  price_class         = var.price_class
  http_version        = "http2and3"
  wait_for_deployment = false

  # Origin 1: S3 static assets
  origin {
    domain_name              = var.s3_bucket_domain_name
    origin_id                = "s3-app-assets"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
  }

  # Origin 2: ALB for dynamic /api/* traffic
  origin {
    domain_name = var.alb_dns_name
    origin_id   = "alb-api"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Default behavior: S3 static assets (cached)
  default_cache_behavior {
    target_origin_id       = "s3-app-assets"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    min_ttl     = 0
    default_ttl = 86400
    max_ttl     = 31536000
  }

  # Ordered behavior: /api/* → ALB (no caching)
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "alb-api"
    viewer_protocol_policy = "https-only"
    compress               = true
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Origin", "Accept", "Content-Type", "Host"]
      cookies { forward = "all" }
    }

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    acm_certificate_arn      = var.acm_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  logging_config {
    bucket          = var.logs_bucket_domain_name
    prefix          = "cloudfront/"
    include_cookies = false
  }

  tags = var.tags
}
