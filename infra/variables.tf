variable "domain" {
  description = "Full subdomain the site is served from, e.g. showcase.dram-soc.org"
  type        = string
  default     = "showcase.dram-soc.org"
}

variable "region" {
  description = "Primary AWS region for the site bucket, Lambda, and API Gateway."
  type        = string
  default     = "us-west-2"
}

variable "owner_email" {
  description = "Email address that receives contact form submissions via SES."
  type        = string
}

variable "ses_verified_sender" {
  description = "SES-verified sender address the contact Lambda sends from."
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch log retention for the Lambda + CloudFront logs."
  type        = number
  default     = 30
}

variable "price_class" {
  description = "CloudFront price class. PriceClass_100 = US/EU only (cheapest)."
  type        = string
  default     = "PriceClass_100"
}

variable "site_domain" {
  description = "Name domain that serves the resume at / and this showcase under site_path."
  type        = string
  default     = "desiramirez.com"
}

variable "site_path" {
  description = "Path the showcase is served under on site_domain. Must match `base` in site/astro.config.mjs."
  type        = string
  default     = "/tokyo-zero"
}

variable "resume_bucket" {
  description = "Bucket owned by the soc-detection-lab stack whose apex/ prefix holds the resume page."
  type        = string
  default     = "dram-soc-dashboard-frontend"
}
