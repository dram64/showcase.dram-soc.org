# Passive DR replica of the site bucket in us-east-1. CloudFront's origin
# group falls back to this bucket on 5xx/timeout. Cross-region replication
# keeps them in sync — writes to the primary land here within seconds.

resource "aws_s3_bucket" "site_dr" {
  provider = aws.us_east_1
  bucket   = "${var.domain}-dr"
}

resource "aws_s3_bucket_public_access_block" "site_dr" {
  provider                = aws.us_east_1
  bucket                  = aws_s3_bucket.site_dr.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "site_dr" {
  provider = aws.us_east_1
  bucket   = aws_s3_bucket.site_dr.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site_dr" {
  provider = aws.us_east_1
  bucket   = aws_s3_bucket.site_dr.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "site_dr_bucket" {
  statement {
    sid       = "AllowCloudFrontOACRead"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site_dr.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.site.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "site_dr" {
  provider = aws.us_east_1
  bucket   = aws_s3_bucket.site_dr.id
  policy   = data.aws_iam_policy_document.site_dr_bucket.json
}

# Cross-region replication role — S3 assumes it to copy from primary to DR.
resource "aws_iam_role" "replication" {
  name = "${replace(var.domain, ".", "-")}-s3-replication"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "replication" {
  role = aws_iam_role.replication.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket",
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging",
        ]
        Resource = [
          aws_s3_bucket.site.arn,
          "${aws_s3_bucket.site.arn}/*",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags",
        ]
        Resource = "${aws_s3_bucket.site_dr.arn}/*"
      },
    ]
  })
}

resource "aws_s3_bucket_replication_configuration" "site_to_dr" {
  # Depend on versioning being enabled on both buckets (replication needs it).
  depends_on = [
    aws_s3_bucket_versioning.site,
    aws_s3_bucket_versioning.site_dr,
  ]

  role   = aws_iam_role.replication.arn
  bucket = aws_s3_bucket.site.id

  rule {
    id     = "site-to-dr"
    status = "Enabled"

    filter {}

    delete_marker_replication {
      status = "Enabled"
    }

    destination {
      bucket        = aws_s3_bucket.site_dr.arn
      storage_class = "STANDARD"
    }
  }
}
