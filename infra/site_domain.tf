# desiramirez.com: one distribution puts both sites on the name domain. The
# resume page is the default behavior, read from the soc-detection-lab
# stack's bucket under apex/ (that stack's bucket policy has to allow this
# distribution). The showcase sits under var.site_path and reads the same
# primary/DR origin group as showcase.dram-soc.org; the router strips the
# prefix, so the bucket layout and the deploy sync stay as they are.
# DNS is in Cloudflare; see the site_domain_* outputs.

resource "aws_acm_certificate" "site_domain" {
  provider                  = aws.us_east_1
  domain_name               = var.site_domain
  subject_alternative_names = ["www.${var.site_domain}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# Same flow as acm.tf: apply waits here until the CNAMEs from the
# site_domain_acm_validation_records output are in Cloudflare.
resource "aws_acm_certificate_validation" "site_domain" {
  provider        = aws.us_east_1
  certificate_arn = aws_acm_certificate.site_domain.arn

  timeouts {
    create = "45m"
  }
}

data "aws_s3_bucket" "resume" {
  provider = aws.us_east_1
  bucket   = var.resume_bucket
}

# The dashboard stack's CSP for the same page, minus the API Gateway
# connect-src that only its dashboard SPA needs. The resume has no scripts.
resource "aws_cloudfront_response_headers_policy" "resume" {
  name    = "${replace(var.site_domain, ".", "-")}-resume-headers"
  comment = "Security headers for the resume page at ${var.site_domain}/"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 63072000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }
    content_security_policy {
      content_security_policy = join(" ", [
        "default-src 'self';",
        "script-src 'self';",
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com;",
        "img-src 'self' data:;",
        "font-src 'self' data: https://fonts.gstatic.com;",
        "object-src 'none';",
        "base-uri 'self';",
        "frame-ancestors 'none'",
      ])
      override = true
    }
    content_type_options { override = true }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
  }

  custom_headers_config {
    items {
      header   = "Permissions-Policy"
      value    = "geolocation=(), microphone=(), camera=(), payment=()"
      override = true
    }
  }
}

# Viewer-request router for both behaviors:
#   - www (and the bare *.cloudfront.net name) 301 to the apex,
#   - the bare site_path 301s to site_path/ so the showcase's links resolve,
#   - site_path/... loses its prefix, since the bucket is laid out from /,
#   - directory-style paths get index.html, as in cloudfront.tf.
resource "aws_cloudfront_function" "site_domain_router" {
  name    = "${replace(var.site_domain, ".", "-")}-router"
  runtime = "cloudfront-js-2.0"
  publish = true
  comment = "Canonical host, ${var.site_path} prefix strip, index.html rewrite."
  code    = <<-EOT
    function handler(event) {
      var request = event.request;
      var host = request.headers.host ? request.headers.host.value : '';
      var uri = request.uri;

      if (host !== '${var.site_domain}' || uri === '${var.site_path}') {
        var query = [];
        for (var key in request.querystring) {
          var param = request.querystring[key];
          var values = param.multiValue ? param.multiValue : [param];
          for (var i = 0; i < values.length; i++) {
            query.push(key + '=' + values[i].value);
          }
        }
        var path = uri === '${var.site_path}' ? uri + '/' : uri;
        return {
          statusCode: 301,
          statusDescription: 'Moved Permanently',
          headers: {
            location: { value: 'https://${var.site_domain}' + path + (query.length ? '?' + query.join('&') : '') }
          }
        };
      }

      if (uri.indexOf('${var.site_path}/') === 0) {
        uri = uri.substring(${length(var.site_path)});
      }
      if (uri.endsWith('/')) {
        uri += 'index.html';
      } else if (!uri.includes('.')) {
        uri += '/index.html';
      }
      request.uri = uri;
      return request;
    }
  EOT
}

resource "aws_cloudfront_distribution" "site_domain" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.site_domain}: resume at /, showcase at ${var.site_path}/"
  default_root_object = "index.html"
  price_class         = var.price_class
  aliases             = [var.site_domain, "www.${var.site_domain}"]

  origin {
    domain_name              = data.aws_s3_bucket.resume.bucket_regional_domain_name
    origin_id                = "s3-resume"
    origin_path              = "/apex"
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "s3-primary-${var.domain}"
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  origin {
    domain_name              = aws_s3_bucket.site_dr.bucket_regional_domain_name
    origin_id                = "s3-dr-${var.domain}"
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  origin_group {
    origin_id = "site-origin-group"

    failover_criteria {
      status_codes = [403, 404, 500, 502, 503, 504]
    }

    member { origin_id = "s3-primary-${var.domain}" }
    member { origin_id = "s3-dr-${var.domain}" }
  }

  default_cache_behavior {
    target_origin_id       = "s3-resume"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6" # Managed-CachingOptimized
    response_headers_policy_id = aws_cloudfront_response_headers_policy.resume.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.site_domain_router.arn
    }
  }

  ordered_cache_behavior {
    path_pattern           = "${var.site_path}/*"
    target_origin_id       = "site-origin-group"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6" # Managed-CachingOptimized
    response_headers_policy_id = aws_cloudfront_response_headers_policy.site.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.site_domain_router.arn
    }
  }

  # /404.html goes through the default behavior, so a miss on either site
  # gets the resume bucket's apex/404.html.
  custom_error_response {
    error_code            = 403
    response_code         = 404
    response_page_path    = "/404.html"
    error_caching_min_ttl = 60
  }

  custom_error_response {
    error_code            = 404
    response_code         = 404
    response_page_path    = "/404.html"
    error_caching_min_ttl = 60
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.site_domain.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  # Same bucket and prefix as the showcase distribution, so the Athena table
  # behind /insights covers both hostnames.
  logging_config {
    bucket          = aws_s3_bucket.logs.bucket_domain_name
    include_cookies = false
    prefix          = "cloudfront/"
  }
}
