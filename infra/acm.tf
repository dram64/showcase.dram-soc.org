resource "aws_acm_certificate" "site" {
  provider          = aws.us_east_1
  domain_name       = var.domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# ACM validation depends on a CNAME the user adds at Cloudflare (see outputs).
# We can't wait on validation in-band, so validation completion is done via a
# separate `terraform apply -target=aws_acm_certificate_validation.site` after
# the DNS record propagates. Terraform will poll ACM until it flips to ISSUED.
resource "aws_acm_certificate_validation" "site" {
  provider        = aws.us_east_1
  certificate_arn = aws_acm_certificate.site.arn

  timeouts {
    create = "45m"
  }
}
