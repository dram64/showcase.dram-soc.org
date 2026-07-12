# showcase.dram-soc.org

Personal portfolio. Design case study (Tokyo Zero merch line) paired with the
serverless AWS stack the site runs on.

Live at [showcase.dram-soc.org](https://showcase.dram-soc.org). The design
writeup is at [/process](https://showcase.dram-soc.org/process); the infra
walkthrough is at [/architecture](https://showcase.dram-soc.org/architecture).

## Layout

```
.
├── site/           Astro static site (frontend)
│   ├── src/pages/  routes: /, /work, /catalog, /process, /architecture,
│   │               /status, /insights, /contact
│   ├── src/layouts/ Base + Gryphline shells
│   └── public/     images, fonts, favicon, sample JSON for ops pages
├── infra/          Terraform for every AWS resource
│   ├── main.tf, s3.tf, cloudfront.tf, acm.tf, dns.tf, failover.tf
│   ├── contact.tf, synthetics.tf, digest.tf, analytics.tf, budget.tf
│   └── lambdas/{contact,digest,canary}
└── .github/workflows/
    ├── deploy.yml     Astro build → S3 sync (primary + DR) → CF invalidate
    └── terraform.yml  fmt / init / validate / plan on PR; apply on merge
```

## Running locally

```bash
cd site
npm install
npm run dev   # http://localhost:4321
```

The contact form points at an API Gateway endpoint by default. To point it
somewhere else:

```bash
cp .env.example .env
# edit PUBLIC_CONTACT_API
```

## Deploying

Push to `main`. Path filters mean site changes and infra changes deploy
independently.

- **Site changes** (`site/**`) — GitHub Actions runs `astro build`, syncs
  `dist/` to the primary + DR buckets, then invalidates CloudFront.
- **Infra changes** (`infra/**`) — PRs get a `terraform plan`; merges to
  `main` run `terraform apply`.

Both workflows use AWS OIDC federation. There are no long-lived AWS keys
in the repo.

First-time setup lives in [`infra/README.md`](./infra/README.md).

### GitHub Actions secrets + variables

| Type     | Name                          |
|----------|-------------------------------|
| Secret   | `AWS_DEPLOY_ROLE_ARN`         |
| Secret   | `AWS_TF_ROLE_ARN`             |
| Secret   | `OWNER_EMAIL`                 |
| Secret   | `SES_SENDER`                  |
| Variable | `SITE_BUCKET`                 |
| Variable | `CLOUDFRONT_DISTRIBUTION_ID`  |
| Variable | `PUBLIC_CONTACT_API`          |

## License

Site code is MIT. Character illustration and brand assets are © dram; all
rights reserved.
