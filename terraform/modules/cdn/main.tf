# AWS-managed policies: no hand-rolled cache keys to maintain.
data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}


# Forwards everything the viewer sent (Host, cookies, query strings) plus CloudFront-* headers,
# notably CloudFront-Forwarded-Proto, which tells Magnolia the viewer used HTTPS.
data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewerAndCloudFrontHeaders-2022-06"
}

data "aws_cloudfront_response_headers_policy" "security_headers" {
  name = "Managed-SecurityHeadersPolicy"
}

locals {
  origin_id = "alb"

  # Theme/UI assets that are identical for every visitor. Everything else is dynamic
  # (AdminCentral is authenticated), so the default behaviour does not cache.
  static_path_patterns = ["/.resources/*", "/VAADIN/*"]
}

# Static UI assets. Like Managed-CachingOptimized, but query strings are part of the cache key:
# Vaadin and Magnolia bust caches with ?v=<version>, and with the managed policy every version
# collapsed into one cached object, so stale JS could be served for up to an hour after an
# upgrade. TTLs follow the origin's Cache-Control (min 0, so max-age=0 really means "don't keep").
resource "aws_cloudfront_cache_policy" "static_assets" {
  name        = "${var.name}-static-assets"
  comment     = "Magnolia/Vaadin static assets: origin TTLs, query strings in the cache key"
  min_ttl     = 0
  default_ttl = 86400    # when the origin sends no Cache-Control
  max_ttl     = 31536000 # 1 year

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true

    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "all"
    }
  }
}

resource "aws_cloudfront_distribution" "this" {
  enabled         = true
  comment         = "${var.name}: Magnolia CMS"
  price_class     = var.price_class
  http_version    = "http2and3"
  is_ipv6_enabled = true

  origin {
    origin_id   = local.origin_id
    domain_name = var.alb_dns_name

    custom_origin_config {
      http_port  = 80
      https_port = 443
      # No custom domain means no ACM certificate on the ALB; see README "Known limitations".
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
      origin_read_timeout    = 60
    }

    custom_header {
      name  = var.origin_verify_header_name
      value = var.origin_verify_header_value
    }
  }

  default_cache_behavior {
    target_origin_id       = local.origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id            = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.all_viewer.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id
  }

  dynamic "ordered_cache_behavior" {
    for_each = local.static_path_patterns

    content {
      path_pattern           = ordered_cache_behavior.value
      target_origin_id       = local.origin_id
      viewer_protocol_policy = "redirect-to-https"
      allowed_methods        = ["GET", "HEAD"]
      cached_methods         = ["GET", "HEAD"]
      compress               = true

      cache_policy_id            = aws_cloudfront_cache_policy.static_assets.id
      response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
