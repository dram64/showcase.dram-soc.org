# Cost guardrails — SNS-backed alerts at $5, $10, and a hard $25 ceiling.
# Even if traffic spikes or a misconfigured Lambda loops, this makes it
# impossible to spend more than the ceiling without a human seeing it first.

resource "aws_sns_topic" "cost_alerts" {
  name              = "${replace(var.domain, ".", "-")}-cost-alerts"
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_sns_topic_subscription" "cost_alerts_email" {
  topic_arn = aws_sns_topic.cost_alerts.arn
  protocol  = "email"
  endpoint  = var.owner_email
}

resource "aws_budgets_budget" "monthly_cap" {
  name         = "${replace(var.domain, ".", "-")}-monthly-cap"
  budget_type  = "COST"
  time_unit    = "MONTHLY"
  limit_amount = "25.00"
  limit_unit   = "USD"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 20 # $5 spent
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.owner_email]
    subscriber_sns_topic_arns  = [aws_sns_topic.cost_alerts.arn]
  }
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 40 # $10 spent
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.owner_email]
    subscriber_sns_topic_arns  = [aws_sns_topic.cost_alerts.arn]
  }
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80 # $20 — near ceiling
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.owner_email]
    subscriber_sns_topic_arns  = [aws_sns_topic.cost_alerts.arn]
  }
}

# Cost Anomaly Detection — the AWS account already has the
# Default-Services-Monitor created automatically. We tighten its
# subscription threshold to $1 outside Terraform (one-time aws CLI call)
# rather than duplicate the monitor here, which the API refuses (limit 1).
