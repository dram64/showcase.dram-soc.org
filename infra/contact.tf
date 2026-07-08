data "archive_file" "contact_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambdas/contact"
  output_path = "${path.module}/build/contact.zip"
}

resource "aws_iam_role" "contact_lambda" {
  name = "${replace(var.domain, ".", "-")}-contact-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "contact_basic" {
  role       = aws_iam_role.contact_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "contact_xray" {
  role       = aws_iam_role.contact_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy" "contact_ses" {
  name = "ses-send"
  role = aws_iam_role.contact_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ses:SendEmail", "ses:SendRawEmail"]
      Resource = "*"
      Condition = {
        StringEquals = {
          "ses:FromAddress" = var.ses_verified_sender
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "contact_ddb" {
  name = "ddb-write"
  role = aws_iam_role.contact_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:PutItem"]
      Resource = aws_dynamodb_table.messages.arn
    }]
  })
}

resource "aws_cloudwatch_log_group" "contact" {
  name              = "/aws/lambda/${replace(var.domain, ".", "-")}-contact"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "contact" {
  function_name    = "${replace(var.domain, ".", "-")}-contact"
  role             = aws_iam_role.contact_lambda.arn
  runtime          = "nodejs20.x"
  handler          = "index.handler"
  filename         = data.archive_file.contact_zip.output_path
  source_code_hash = data.archive_file.contact_zip.output_base64sha256
  timeout          = 8
  memory_size      = 256

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      RECIPIENT_EMAIL = var.owner_email
      SENDER_EMAIL    = var.ses_verified_sender
      TABLE_NAME      = aws_dynamodb_table.messages.name
      ALLOWED_ORIGIN  = "https://${var.domain}"
    }
  }

  depends_on = [aws_cloudwatch_log_group.contact]
}

resource "aws_dynamodb_table" "messages" {
  name         = "${replace(var.domain, ".", "-")}-contact-messages"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }
}

# HTTP API v2 — cheaper + faster than REST API. CORS handled at the gateway
# rather than in Lambda so preflights don't cost a Lambda invocation.
resource "aws_apigatewayv2_api" "contact" {
  name          = "${replace(var.domain, ".", "-")}-contact-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["https://${var.domain}"]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["content-type"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_stage" "contact" {
  api_id      = aws_apigatewayv2_api.contact.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit   = 20
    throttling_rate_limit    = 10
    detailed_metrics_enabled = true
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.contact_api.arn
    format = jsonencode({
      requestId  = "$context.requestId"
      ip         = "$context.identity.sourceIp"
      status     = "$context.status"
      latency_ms = "$context.responseLatency"
      path       = "$context.path"
    })
  }
}

resource "aws_cloudwatch_log_group" "contact_api" {
  name              = "/aws/http-api/${replace(var.domain, ".", "-")}-contact"
  retention_in_days = var.log_retention_days
}

resource "aws_apigatewayv2_integration" "contact" {
  api_id                 = aws_apigatewayv2_api.contact.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.contact.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "contact" {
  api_id    = aws_apigatewayv2_api.contact.id
  route_key = "POST /contact"
  target    = "integrations/${aws_apigatewayv2_integration.contact.id}"
}

resource "aws_lambda_permission" "contact_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.contact.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.contact.execution_arn}/*/*"
}
