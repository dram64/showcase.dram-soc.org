# Bootstrap — one-time manual steps

Terraform (`infra/`) provisions the whole stack, but a handful of things have to
exist before `terraform apply` can succeed. Do these once, in order. Everything
else is automated.

Rough time: 45 minutes if nothing goes sideways.

---

## 0. Pre-reqs

- AWS account (root or admin creds you can use locally for the bootstrap).
- `aws` CLI configured (`aws configure`) with those creds, region `us-west-2`.
- `terraform` CLI installed (any 1.6+).
- Access to Cloudflare DNS for `dram-soc.org`.
- Access to GitHub repo settings for `dram64/showcase.dram-soc.org`.

---

## 1. Create the Terraform state backend

Terraform stores state in an S3 bucket and locks via DynamoDB. These
resources have to exist **before** `terraform init` runs, because they
themselves back the state.

```bash
# S3 bucket for tfstate
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

# DynamoDB table for state locking
aws dynamodb create-table \
  --table-name dram-soc-tfstate-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-west-2
```

---

## 2. Set up GitHub OIDC → AWS

The `terraform.yml` and `deploy.yml` workflows both assume IAM roles via
GitHub's OIDC provider. One-time setup per repo.

### 2a. Register the OIDC provider (once per account)

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### 2b. Create the Terraform apply role

File: `bootstrap/tf-role-trust.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": "repo:dram64/showcase.dram-soc.org:*"
      }
    }
  }]
}
```

```bash
aws iam create-role \
  --role-name gha-terraform-apply \
  --assume-role-policy-document file://bootstrap/tf-role-trust.json

# Broad admin for the initial apply. Tighten later.
aws iam attach-role-policy \
  --role-name gha-terraform-apply \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

### 2c. Create the site-deploy role (narrower)

Similar trust policy. Attach a scoped inline policy that only permits:

- `s3:PutObject`, `s3:DeleteObject`, `s3:ListBucket` on both site buckets
- `cloudfront:CreateInvalidation` on the distribution

File-level details in `bootstrap/deploy-role-trust.json` and
`bootstrap/deploy-role-policy.json` (same structure as 2b, narrower actions).

### 2d. Copy the role ARNs into GitHub secrets

Settings → Secrets and variables → Actions:

- **Secrets**
  - `AWS_TF_ROLE_ARN` = arn of `gha-terraform-apply`
  - `AWS_DEPLOY_ROLE_ARN` = arn of `gha-site-deploy`
  - `OWNER_EMAIL` = desiramirez62200@gmail.com
  - `SES_SENDER` = desiramirez62200@gmail.com
- **Variables**
  - `SITE_BUCKET` = showcase.dram-soc.org
  - `CLOUDFRONT_DISTRIBUTION_ID` = (fill in after step 4)
  - `PUBLIC_CONTACT_API` = (fill in after step 4)

---

## 3. Verify the SES sender

SES sandbox mode requires the sender AND every recipient to be verified.
Since the contact form only sends to yourself, one verification covers both.

```bash
aws ses verify-email-identity \
  --region us-west-2 \
  --email-address desiramirez62200@gmail.com
```

Then click the confirmation link in the Gmail inbox. Optional: request
production access to leave the sandbox if you ever want to send to
recipients other than the owner.

---

## 4. First Terraform apply (partial — ACM will hang)

```bash
cd infra
terraform init
terraform apply
```

This will provision most resources. When it gets to
`aws_acm_certificate_validation.site` it will **hang up to 45 minutes**
waiting for DNS validation. That's expected.

While it's hanging, in a **second terminal**:

```bash
cd infra
terraform output acm_validation_records
```

The output is a list of `{ name, value, type }` CNAMEs. Add each one to
Cloudflare DNS (Cloudflare → DNS → Records → Add), with:

- Type: **CNAME**
- Name: the `name` from the output (minus the domain suffix Cloudflare
  will re-append)
- Target: the `value`
- Proxy status: **DNS only** (grey cloud, not orange)
- TTL: Auto

Once the CNAMEs propagate (usually 60 seconds), the hanging apply from
the first terminal will resume, ACM will flip to `ISSUED`, and CloudFront
will finish creating.

---

## 5. Add the site CNAME to Cloudflare

```bash
terraform output cloudflare_cname_instruction
# → In Cloudflare DNS: create CNAME 'showcase.dram-soc.org' -> 'dxxxxxxx.cloudfront.net' with PROXY OFF
```

Add that CNAME. Same rules: **DNS only** (grey cloud), TTL Auto.

Wait ~2 minutes for DNS to propagate. `dig showcase.dram-soc.org CNAME`
should return the CloudFront domain.

---

## 6. Confirm the SNS subscription

Terraform provisioned an SNS topic for cost + canary alerts and subscribed
your email. Check your inbox for a `AWS Notification - Subscription
Confirmation` message and click **Confirm subscription**. Without this
step, alarms fire silently.

---

## 7. Fill in the GitHub variables you couldn't fill in earlier

```bash
terraform output cloudfront_distribution_id  # → CLOUDFRONT_DISTRIBUTION_ID
terraform output contact_api_endpoint        # → PUBLIC_CONTACT_API
```

Settings → Secrets and variables → Actions → Variables → paste both.

---

## 8. Trigger a real deploy + populate the digest

Push any change to `site/` or run the deploy workflow manually. Once the
site is deployed to S3 and CloudFront invalidates:

Manually invoke the digest Lambda so the ops pages have data before the
first nightly cron:

```bash
aws lambda invoke \
  --function-name showcase-dram-soc-org-digest \
  --region us-west-2 \
  /tmp/digest-out.json
cat /tmp/digest-out.json
# → { "ok": true, "wrote": ["status.json", "insights.json"] }
```

Refresh `/status` and `/insights` — they should now show live data from
the canary and (once CloudFront logs accumulate) Athena.

---

## 9. Recurring operations

None. Nightly EventBridge fires the digest at 03:00 UTC. Hourly Synthetics
canary is auto-scheduled. Terraform changes deploy via merge to `main`.

If anything breaks:

- **Canary alarm** → email hits the SNS topic → check `/status` for the
  failed URL and CloudWatch console for the run's screenshot.
- **Budget alert** → email hits the SNS topic → check Cost Explorer.
- **Contact form 5xx** → X-Ray trace map has the full request path.

---

## Rollback

Undoing this is a `terraform destroy` in the `infra/` directory. That will
wipe every resource this stack owns. It **won't** delete the tfstate
bucket, the OIDC provider, the IAM roles, or the SES verification — those
are pre-Terraform bootstrap resources. Clean those up manually if you're
tearing down for good.

The site itself (`site/` build → S3 buckets) will remain in S3 unless
you also empty the buckets. `--force` on destroy handles that if the
buckets are marked force_destroy in Terraform (the log/canary/athena
buckets are; the site buckets deliberately are not, to prevent accidents).
