resource "aws_acm_certificate" "site" {
  provider          = aws.us_east_1
  domain_name       = var.domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# ACM validation depends on a CNAME added in Cloudflare — see outputs.tf
# for the exact record. Terraform polls ACM until the cert flips to ISSUED
# (up to 45 min); add the CNAME while apply is waiting.
resource "aws_acm_certificate_validation" "site" {
  provider        = aws.us_east_1
  certificate_arn = aws_acm_certificate.site.arn

  timeouts {
    create = "45m"
  }
}
