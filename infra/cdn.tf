data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

# Our own policy instead of the managed one: explicit HSTS and CSP, and
# Checkov's plan scan can see it (it missed the managed policy data source).
resource "aws_cloudfront_response_headers_policy" "security" {
  name    = "${var.project}-security-headers"
  comment = "HSTS, CSP and the usual hardening headers"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 63072000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }
    content_security_policy {
      content_security_policy = "default-src 'none'; style-src 'unsafe-inline'; img-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
      override                = true
    }
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
  }
}

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${var.project}-site"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "site" {
  #checkov:skip=CKV_AWS_68:WAF costs more per month than this demo. Add it before serving anything dynamic.
  #checkov:skip=CKV2_AWS_47:Follows CKV_AWS_68: no WAF attached yet.
  #checkov:skip=CKV_AWS_86:CloudFront standard logs need another bucket. Out of scope for the demo.
  #checkov:skip=CKV_AWS_374:Public site, no reason to block countries.
  #checkov:skip=CKV_AWS_310:Single-region demo. Failover needs a second origin bucket.
  #checkov:skip=CKV2_AWS_42:No custom domain, so the default *.cloudfront.net certificate is used.
  #checkov:skip=CKV_AWS_174:The default certificate fixes the TLS policy. A custom certificate would set TLSv1.2_2021.
  enabled             = true
  comment             = "${var.project} static site"
  price_class         = "PriceClass_100"
  default_root_object = "index.html"

  origin {
    origin_id                = "site-bucket"
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    target_origin_id           = "site-bucket"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    cache_policy_id            = data.aws_cloudfront_cache_policy.optimized.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id
    compress                   = true
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
