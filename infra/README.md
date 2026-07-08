# dram-soc.org — infrastructure

Terraform for the dram-soc.org portfolio site. Provisions:

- **S3** — origin bucket (private, OAC-only access) + logs bucket with 30-day lifecycle
- **CloudFront** — CDN with HTTPS redirect, security headers policy, CloudFront Function for pretty-URL rewrites
- **ACM** — TLS cert in `us-east-1` (CloudFront requirement) with DNS validation
- **Route 53** — A-record aliases for apex + `www`
- **Lambda + API Gateway (HTTP API v2)** — `POST /contact` endpoint for the contact form
- **SES** — outbound email from the contact Lambda (identity must be pre-verified out of band)
- **DynamoDB** — audit table for contact-form submissions (pay-per-request, encrypted, PITR)
- **CloudWatch** — log groups for the Lambda + HTTP API access logs, 30-day retention

## First-time setup

1. Verify the sender identity in SES (once): `no-reply@dram-soc.org` or a Route 53–managed subdomain.
2. Create the state backend bucket + lock table (one-time bootstrap):

```bash
aws s3 mb s3://dram-soc-tfstate --region us-west-2
aws s3api put-bucket-versioning --bucket dram-soc-tfstate --versioning-configuration Status=Enabled
aws dynamodb create-table \
  --table-name dram-soc-tfstate-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-west-2
```

3. Copy the vars template and fill in your values:

```bash
cp terraform.tfvars.example terraform.tfvars
```

4. Install Lambda dependencies (Terraform zips the dir as-is):

```bash
cd lambdas/contact && npm install --omit=dev && cd ../..
```

5. Apply:

```bash
terraform init
terraform plan
terraform apply
```

## Outputs the CI/CD pipeline consumes

- `site_bucket` — destination for `aws s3 sync` on deploy
- `cloudfront_distribution_id` — target for cache invalidation
- `contact_api_endpoint` — injected into the Astro build as `PUBLIC_CONTACT_API`

## Approximate monthly cost (portfolio-scale traffic)

| Service         | Cost/mo | Notes                                    |
|-----------------|---------|------------------------------------------|
| S3 (site+logs)  | ~$0.05  | <1 GB stored, minimal requests           |
| CloudFront      | ~$0.20  | PriceClass_100, <10 GB egress            |
| Route 53        | $0.50   | Hosted zone (already existed)            |
| ACM             | $0.00   | Free                                     |
| Lambda          | $0.00   | Free tier covers <1M invocations         |
| API Gateway     | ~$0.00  | Free tier covers <1M requests            |
| DynamoDB        | ~$0.00  | Pay-per-request, negligible writes       |
| SES             | ~$0.00  | Free tier covers 62,000 emails from Lambda|
| CloudWatch logs | ~$0.05  | 30-day retention on Lambda + HTTP API    |
| **Total**       | **~$0.80/mo** | after Route 53's fixed $0.50 zone fee |
