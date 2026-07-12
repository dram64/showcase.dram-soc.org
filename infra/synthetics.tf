# CloudWatch Synthetics canary — probes 3 pages hourly from us-west-2 and
# verifies each returns 200 with the expected marker string. Failure fires
# a CloudWatch alarm → SNS topic (shared with cost alerts).

resource "aws_s3_bucket" "canary_artifacts" {
  bucket        = "${var.domain}-canary"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "canary_artifacts" {
  bucket                  = aws_s3_bucket.canary_artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "canary_artifacts" {
  bucket = aws_s3_bucket.canary_artifacts.id
  rule {
    id     = "expire-old-screenshots"
    status = "Enabled"
    filter {}
    expiration { days = 14 }
  }
}

data "archive_file" "canary_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambdas/canary"
  output_path = "${path.module}/build/canary.zip"
}

resource "aws_iam_role" "canary" {
  name = "${replace(var.domain, ".", "-")}-canary"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "canary" {
  role = aws_iam_role.canary.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetBucketLocation",
          "s3:ListAllMyBuckets",
        ]
        Resource = [
          aws_s3_bucket.canary_artifacts.arn,
          "${aws_s3_bucket.canary_artifacts.arn}/*",
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:CreateLogGroup", "logs:PutLogEvents"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "cloudwatch:PutMetricData"
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "CloudWatchSynthetics"
          }
        }
      },
    ]
  })
}

resource "aws_synthetics_canary" "portfolio" {
  name                 = "${substr(replace(var.domain, ".", "-"), 0, 21)}"
  artifact_s3_location = "s3://${aws_s3_bucket.canary_artifacts.bucket}/"
  execution_role_arn   = aws_iam_role.canary.arn
  runtime_version      = "syn-nodejs-puppeteer-9.1"
  handler              = "index.handler"
  zip_file             = data.archive_file.canary_zip.output_path
  start_canary         = true

  schedule {
    expression          = "rate(1 hour)"
    duration_in_seconds = 0
  }

  run_config {
    timeout_in_seconds = 60
    memory_in_mb       = 1024
    active_tracing     = true
  }

  success_retention_period = 14
  failure_retention_period = 30
}

resource "aws_cloudwatch_metric_alarm" "canary_failed" {
  alarm_name          = "${replace(var.domain, ".", "-")}-canary-failed"
  alarm_description   = "showcase.dram-soc.org canary has failed at least once in the last 15 min"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "SuccessPercent"
  namespace           = "CloudWatchSynthetics"
  period              = 900
  statistic           = "Average"
  threshold           = 100
  treat_missing_data  = "breaching"

  dimensions = {
    CanaryName = aws_synthetics_canary.portfolio.name
  }

  alarm_actions = [aws_sns_topic.cost_alerts.arn]
  ok_actions    = [aws_sns_topic.cost_alerts.arn]
}
