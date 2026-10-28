output "site_bucket" {
  description = "S3 bucket the site is deployed to via CI/CD."
  value       = aws_s3_bucket.site.id
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (used by CI/CD for cache invalidation)."
  value       = aws_cloudfront_distribution.site.id
}

output "cloudfront_domain" {
  description = "CloudFront domain. Add this to Cloudflare as a CNAME for showcase.dram-soc.org (proxied=false)."
  value       = aws_cloudfront_distribution.site.domain_name
}

output "contact_api_endpoint" {
  description = "HTTP API endpoint the contact form POSTs to. Site build embeds this."
  value       = "${aws_apigatewayv2_api.contact.api_endpoint}/contact"
}

# ACM DNS-01 validation — you paste these into Cloudflare (as unproxied CNAMEs)
# to prove domain ownership. `aws_acm_certificate_validation` polls until they
# resolve, then the cert flips to ISSUED.
output "acm_validation_records" {
  description = "CNAMEs to add at Cloudflare (unproxied) to validate the TLS cert."
  value = [
    for dvo in aws_acm_certificate.site.domain_validation_options : {
      name  = dvo.resource_record_name
      value = dvo.resource_record_value
      type  = dvo.resource_record_type
    }
  ]
}

output "cloudflare_cname_instruction" {
  description = "One-shot instructions for the site CNAME."
  value       = "In Cloudflare DNS: create CNAME '${var.domain}' -> '${aws_cloudfront_distribution.site.domain_name}' with PROXY OFF (grey cloud). CloudFront handles TLS + CDN itself."
}

output "site_url" {
  description = "Public site URL."
  value       = "https://${var.domain}"
}

output "site_domain_acm_validation_records" {
  description = "CNAMEs to add in the site_domain Cloudflare zone (unproxied) to validate its cert."
  value = [
    for dvo in aws_acm_certificate.site_domain.domain_validation_options : {
      name  = dvo.resource_record_name
      value = dvo.resource_record_value
      type  = dvo.resource_record_type
    }
  ]
}

output "site_domain_distribution_id" {
  description = "Set as the SITE_DISTRIBUTION_ID repo variable so deploys invalidate it."
  value       = aws_cloudfront_distribution.site_domain.id
}

output "site_domain_distribution_arn" {
  description = "Goes in the soc-detection-lab resume bucket policy so this distribution can read apex/."
  value       = aws_cloudfront_distribution.site_domain.arn
}

output "site_domain_cname_instruction" {
  description = "Cloudflare records for the name domain."
  value       = "In the ${var.site_domain} Cloudflare zone: CNAME '@' and 'www' -> '${aws_cloudfront_distribution.site_domain.domain_name}' with PROXY OFF (grey cloud)."
}
