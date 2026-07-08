# Nightly digest — EventBridge Scheduler → Lambda → writes JSON to both
# site buckets. Static pages (/cost, /status, /insights) fetch the JSON
# client-side. All queries stay well within free tier at portfolio scale.

data "archive_file" "digest_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambdas/digest"
  output_path = "${path.module}/build/digest.zip"
}

resource "aws_iam_role" "digest" {
  name = "${replace(var.domain, ".", "-")}-digest"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "digest_basic" {
  role       = aws_iam_role.digest.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "digest" {
  role = aws_iam_role.digest.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ce:GetCostAndUsage"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["synthetics:DescribeCanariesLastRun", "synthetics:GetCanary"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution",
          "athena:GetQueryExecution",
          "athena:GetQueryResults",
          "athena:GetWorkGroup",
        ]
        Resource = [aws_athena_workgroup.portfolio.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetTable",
          "glue:GetPartitions",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.logs.arn,
          "${aws_s3_bucket.logs.arn}/*",
        ]
      },
      {
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetBucketLocation", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.athena_results.arn,
          "${aws_s3_bucket.athena_results.arn}/*",
        ]
      },
      {
        Effect = "Allow"
        Action = ["s3:PutObject"]
        Resource = [
          "${aws_s3_bucket.site.arn}/cost.json",
          "${aws_s3_bucket.site.arn}/status.json",
          "${aws_s3_bucket.site.arn}/insights.json",
          "${aws_s3_bucket.site_dr.arn}/cost.json",
          "${aws_s3_bucket.site_dr.arn}/status.json",
          "${aws_s3_bucket.site_dr.arn}/insights.json",
        ]
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "digest" {
  name              = "/aws/lambda/${replace(var.domain, ".", "-")}-digest"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "digest" {
  function_name    = "${replace(var.domain, ".", "-")}-digest"
  role             = aws_iam_role.digest.arn
  runtime          = "nodejs20.x"
  handler          = "index.handler"
  filename         = data.archive_file.digest_zip.output_path
  source_code_hash = data.archive_file.digest_zip.output_base64sha256
  timeout          = 120
  memory_size      = 512

  tracing_config { mode = "Active" }

  environment {
    variables = {
      SITE_BUCKET      = aws_s3_bucket.site.bucket
      SITE_BUCKET_DR   = aws_s3_bucket.site_dr.bucket
      CANARY_NAME      = aws_synthetics_canary.portfolio.name
      ATHENA_DB        = aws_glue_catalog_database.portfolio.name
      ATHENA_WORKGROUP = aws_athena_workgroup.portfolio.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.digest]
}

# EventBridge Scheduler — nightly at 03:00 UTC (portfolio has low traffic then).
resource "aws_scheduler_schedule" "digest" {
  name                         = "${replace(var.domain, ".", "-")}-digest-nightly"
  schedule_expression          = "cron(0 3 * * ? *)"
  schedule_expression_timezone = "UTC"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.digest.arn
    role_arn = aws_iam_role.scheduler.arn
  }
}

resource "aws_iam_role" "scheduler" {
  name = "${replace(var.domain, ".", "-")}-scheduler"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  role = aws_iam_role.scheduler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_function.digest.arn
    }]
  })
}
