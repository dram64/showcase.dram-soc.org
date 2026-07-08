# dram-soc.org

Personal portfolio site — paired design case study (Tokyo Zero merch line) and cloud engineering showcase (serverless AWS, Terraform, GitHub Actions).

Live: [dram-soc.org](https://dram-soc.org) · Design writeup: [/process](https://dram-soc.org/process) · Architecture: [/architecture](https://dram-soc.org/architecture)

## Repo layout

```
dram-soc.org/
├── site/                Astro static site (frontend)
│   ├── src/pages/       index, work, process, architecture, contact
│   ├── src/layouts/     Base layout shared across pages
│   └── public/          Images, fonts, favicon
├── infra/               Terraform — all AWS resources
│   ├── main.tf          providers + backend
│   ├── s3.tf            site + logs buckets
│   ├── cloudfront.tf    CDN, security headers, URL-rewrite CF Function
│   ├── acm.tf           us-east-1 TLS cert with DNS validation
│   ├── route53.tf       A-record aliases for apex + www
│   ├── contact.tf       Lambda + HTTP API v2 + DynamoDB + SES policy
│   ├── outputs.tf       CI/CD-consumed outputs
│   └── lambdas/contact/ Node 20 contact form handler
└── .github/workflows/
    ├── deploy.yml       build Astro, sync S3, invalidate CloudFront
    └── terraform.yml    fmt + plan on PR, apply on merge to main
```

## Architecture at a glance

```
user ──▶ Route 53 ──▶ CloudFront ──▶ S3 (private, OAC)
                          │
                          └──▶ HTTP API ──▶ Lambda ──▶ SES
                                                └──▶ DynamoDB
```

Full breakdown with cost table, security notes, and reasoning at [/architecture](https://dram-soc.org/architecture).

## Running locally

```bash
cd site
npm install
npm run dev            # http://localhost:4321
```

To point the contact form at your local API or a deployed one:

```bash
cp .env.example .env
# edit PUBLIC_CONTACT_API in .env
```

## Deploying

The site auto-deploys on push to `main`:

- **Site changes** (`site/**`) → GitHub Actions runs `astro build`, `aws s3 sync`, then `cloudfront create-invalidation`.
- **Infra changes** (`infra/**`) → PRs get a `terraform plan` comment; merges to main run `terraform apply`.

Both workflows authenticate to AWS via **OIDC** — no long-lived access keys in the repo.

### First-time infra bootstrap

See [`infra/README.md`](./infra/README.md) for the one-time setup (state bucket, SES verification, `terraform apply`).

### Required GitHub Actions secrets + variables

| Type     | Name                          | Purpose                                      |
|----------|-------------------------------|----------------------------------------------|
| Secret   | `AWS_DEPLOY_ROLE_ARN`         | Role assumed by the `deploy.yml` workflow     |
| Secret   | `AWS_TF_ROLE_ARN`             | Role assumed by the `terraform.yml` workflow  |
| Secret   | `OWNER_EMAIL`                 | Where contact form messages go                |
| Secret   | `SES_SENDER`                  | Verified sender identity                      |
| Variable | `SITE_BUCKET`                 | S3 bucket name (from `terraform output`)      |
| Variable | `CLOUDFRONT_DISTRIBUTION_ID`  | CF distribution ID (from `terraform output`)  |
| Variable | `PUBLIC_CONTACT_API`          | HTTP API endpoint URL for the contact form    |

## Cost

~$0.80/month at portfolio-scale traffic. Full breakdown in [`infra/README.md`](./infra/README.md).

## Why this stack?

- **Static site + edge CDN** — no server to patch, sub-100ms global TTFB, scales to any traffic
- **Serverless contact form** — pay only when someone actually submits (~free in practice)
- **Terraform** — reproducible, versioned, PR-reviewable infra
- **OIDC deploys** — zero-secret CI/CD, IAM policy is the audit trail
- **Free-tier native** — same architecture works for a 100× traffic product with linear cost growth

Reasoning for each service is documented at [/architecture](https://dram-soc.org/architecture).

## License

Site code MIT. Character illustration + brand assets © dram, all rights reserved.
