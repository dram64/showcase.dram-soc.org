# infra

Terraform for showcase.dram-soc.org. One state, one apply.

## What's in here

| File            | What it owns                                              |
|-----------------|-----------------------------------------------------------|
| `main.tf`       | providers + s3/dynamodb state backend                     |
| `variables.tf`  | inputs (domain, region, owner email, SES sender)          |
| `s3.tf`         | origin bucket (private, OAC-only) + CloudFront logs bucket|
| `failover.tf`   | DR site bucket in us-east-1 + cross-region replication    |
| `cloudfront.tf` | distribution, origin group failover, security headers, URL-rewrite CF Function |
| `acm.tf`        | TLS cert in us-east-1 with DNS-01 validation              |
| `dns.tf`        | (empty) DNS lives in Cloudflare — see `outputs.tf`        |
| `contact.tf`    | HTTP API v2 + Node 20 Lambda + DynamoDB audit + SES send  |
| `synthetics.tf` | hourly Puppeteer canary + failure alarm                   |
| `digest.tf`     | nightly EventBridge → Lambda → writes status/insights JSON|
| `analytics.tf`  | Athena workgroup + Glue table over CloudFront logs        |
| `budget.tf`     | AWS Budgets + SNS alerts (shared with canary alarm)       |
| `outputs.tf`    | values consumed by the CI/CD pipeline + Cloudflare CNAMEs |

The lambda source lives under `lambdas/` — one folder per function.

## First-time setup

Rough time: 45 min if nothing goes sideways.

### 1. State backend

The tfstate bucket + lock table must exist before `terraform init` runs.

```bash
aws s3api create-bucket \
  --bucket dram-soc-tfstate \
  --region us-west-2 \
  --create-bucket-configuration LocationConstraint=us-west-2

aws s3api put-bucket-versioning \
  --bucket dram-soc-tfstate \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket dram-soc-tfstate \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws s3api put-public-access-block \
  --bucket dram-soc-tfstate \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

aws dynamodb create-table \
  --table-name dram-soc-tfstate-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-west-2
```

### 2. GitHub OIDC → AWS

Register the provider once per account:

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

Create two roles that trust the repo — `gha-terraform-apply` (Administrator
during initial rollout, tighten later) and `gha-site-deploy` (S3 + CloudFront
invalidation only). The trust policy is a standard `sts:AssumeRoleWithWebIdentity`
scoped to `repo:dram64/showcase.dram-soc.org:*`.

Then set the ARNs as GitHub repo secrets (see the table in the top-level
`README.md`).

### 3. Verify the SES sender

```bash
aws ses verify-email-identity \
  --region us-west-2 \
  --email-address <your@email>
```

Click the confirmation in the inbox. Without this, the contact Lambda can't
send.

### 4. Local variables

```bash
cp terraform.tfvars.example terraform.tfvars
# edit the values
```

### 5. Install lambda deps

```bash
cd lambdas/contact && npm install --omit=dev && cd -
cd lambdas/digest  && npm install --omit=dev && cd -
```

### 6. First apply

```bash
terraform init
terraform apply
```

Apply will pause at `aws_acm_certificate_validation.site` for up to 45 minutes,
waiting on DNS. In a second terminal:

```bash
terraform output acm_validation_records
```

Add each CNAME in Cloudflare (Proxy status: **DNS only**, grey cloud). Apply
will resume as soon as the record propagates.

### 7. Point the domain at CloudFront

```bash
terraform output cloudflare_cname_instruction
```

Add that CNAME in Cloudflare too — again with **DNS only**.

### 8. Confirm the SNS subscription

Terraform subscribes your email to the SNS topic used for canary + budget
alarms. Look for a `Subscription Confirmation` email and click confirm.

### 9. Feed the GitHub variables

```bash
terraform output cloudfront_distribution_id  # → CLOUDFRONT_DISTRIBUTION_ID
terraform output contact_api_endpoint        # → PUBLIC_CONTACT_API
```

### 10. Kick the digest once

The nightly cron fires at 03:00 UTC. To populate `/status` and `/insights`
right away:

```bash
aws lambda invoke \
  --function-name showcase-dram-soc-org-digest \
  --region us-west-2 \
  /tmp/digest-out.json
```

## Ongoing

Nothing. Nightly digest, hourly canary, and CI apply run themselves. Terraform
edits go through PR review; merge to `main` applies.

## Tearing down

`terraform destroy` inside `infra/`. State backend, OIDC provider, IAM roles,
and SES verification are pre-Terraform — delete those by hand if you're done
for good. Site buckets are protected from `--force-destroy` so an accidental
destroy won't nuke the current content.
