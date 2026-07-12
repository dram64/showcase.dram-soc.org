# DNS lives in Cloudflare (existing dram-soc.org zone). See outputs.tf for
# the two CNAMEs that must be added to Cloudflare after `terraform apply`:
#   1. showcase.dram-soc.org  →  <CloudFront domain>
#   2. ACM DNS-01 validation record (proxied=false)
