# Cost Monitoring and Alerts for Storage Optimization

# SNS topic for cost alerts
resource "aws_sns_topic" "cost_alerts" {
  name = "${var.project_name}-${var.environment}-storage-cost-alerts"

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-storage-cost-alerts"
      Type = "Cost-Monitoring"
    }
  )
}

# Email subscription for alerts
resource "aws_sns_topic_subscription" "cost_alerts_email" {
  count = var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.cost_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Budget for S3 storage costs
resource "aws_budgets_budget" "s3_storage" {
  name         = "${var.project_name}-${var.environment}-s3-storage"
  budget_type  = "COST"
  limit_amount = var.storage_budget_amount
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "Service"
    values = ["Amazon Simple Storage Service"]
  }

  cost_filter {
    name = "UsageType"
    values = [
      "DataTransfer-Out-Bytes",
      "StorageUsage",
      "Requests-Tier1",
      "Requests-Tier2"
    ]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 90
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
  }
}

# Budget for CloudWatch Logs costs
resource "aws_budgets_budget" "cloudwatch_logs" {
  name         = "${var.project_name}-${var.environment}-cloudwatch-logs"
  budget_type  = "COST"
  limit_amount = var.logs_budget_amount
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "Service"
    values = ["AmazonCloudWatch"]
  }

  cost_filter {
    name = "UsageType"
    values = [
      "DataProcessing-Bytes",
      "VolumeUsage",
      "DataScanned-Bytes",
      "PutLogEvents"
    ]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
  }
}

# Cost anomaly detector
resource "aws_ce_anomaly_monitor" "storage_costs" {
  name              = "${var.project_name}-${var.environment}-storage-anomaly"
  monitor_type      = "CUSTOM"
  monitor_frequency = "DAILY"

  monitor_specification = jsonencode({
    Dimensions = {
      Key          = "SERVICE"
      Values       = ["Amazon Simple Storage Service", "AmazonCloudWatch"]
      MatchOptions = ["EQUALS"]
    }
  })

  tags = var.common_tags
}

resource "aws_ce_anomaly_subscription" "storage_alerts" {
  name      = "${var.project_name}-${var.environment}-storage-anomaly-alerts"
  frequency = "DAILY"

  monitor_arn_list = [
    aws_ce_anomaly_monitor.storage_costs.arn
  ]

  subscriber {
    type    = "SNS"
    address = aws_sns_topic.cost_alerts.arn
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = ["50"]
    }
  }

  tags = var.common_tags
}

# CloudWatch Dashboard for cost monitoring
resource "aws_cloudwatch_dashboard" "storage_costs" {
  dashboard_name = "${var.project_name}-${var.environment}-storage-costs"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/S3", "BucketSizeBytes", { stat = "Average" }],
            [".", "NumberOfObjects", { stat = "Average", yAxis = "right" }]
          ]
          period = 86400
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "S3 Storage Overview"
          annotations = {
            horizontal = [
              {
                label = "Budget Threshold"
                value = var.storage_budget_amount * 30 # Rough conversion
              }
            ]
          }
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Logs", "IncomingBytes", { stat = "Sum" }],
            [".", "IncomingLogEvents", { stat = "Sum", yAxis = "right" }]
          ]
          period = 86400
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "CloudWatch Logs Ingestion"
        }
      },
      {
        type   = "metric"
        width  = 24
        height = 6
        properties = {
          metrics = [
            ["CWAgent", "S3_Storage_Cost_Daily", { stat = "Sum" }],
            [".", "CloudWatch_Logs_Cost_Daily", { stat = "Sum" }],
            [".", "Total_Storage_Cost_Daily", { stat = "Sum" }]
          ]
          period = 86400
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Daily Storage Costs"
          yAxis = {
            left = {
              label = "Cost (USD)"
            }
          }
        }
      }
    ]
  })
}

# Lambda for custom cost metrics
resource "aws_lambda_function" "cost_calculator" {
  filename      = data.archive_file.cost_calculator.output_path
  function_name = "${var.project_name}-${var.environment}-storage-cost-calculator"
  role          = aws_iam_role.cost_calculator.arn
  handler       = "index.handler"
  runtime       = "python3.9"
  timeout       = 60

  environment {
    variables = {
      METRIC_NAMESPACE = "CWAgent"
      S3_PRICING = jsonencode({
        STANDARD     = 0.023
        STANDARD_IA  = 0.0125
        GLACIER      = 0.004
        DEEP_ARCHIVE = 0.00099
      })
      LOGS_PRICING = jsonencode({
        ingestion = 0.50
        storage   = 0.03
        analysis  = 0.0057
      })
    }
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-cost-calculator"
      Type = "Cost-Monitoring"
    }
  )
}

# EventBridge rule for daily cost calculation
resource "aws_cloudwatch_event_rule" "daily_cost_calculation" {
  name                = "${var.project_name}-${var.environment}-daily-cost-calc"
  description         = "Calculate daily storage costs"
  schedule_expression = "rate(1 day)"

  tags = var.common_tags
}

resource "aws_cloudwatch_event_target" "cost_calculator" {
  rule      = aws_cloudwatch_event_rule.daily_cost_calculation.name
  target_id = "CostCalculatorLambda"
  arn       = aws_lambda_function.cost_calculator.arn
}

resource "aws_lambda_permission" "allow_eventbridge_cost" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_calculator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_cost_calculation.arn
}

# Lambda code
data "archive_file" "cost_calculator" {
  type        = "zip"
  output_path = "${path.module}/cost-calculator.zip"

  source {
    content  = file("${path.module}/cost-calculator.py")
    filename = "index.py"
  }
}

# IAM role for cost calculator
resource "aws_iam_role" "cost_calculator" {
  name = "${var.project_name}-${var.environment}-cost-calculator-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy" "cost_calculator" {
  name = "cost-calculator-policy"
  role = aws_iam_role.cost_calculator.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets",
          "s3:GetBucketLocation",
          "s3:ListBucket",
          "s3:GetBucketTagging",
          "s3:GetBucketLifecycleConfiguration",
          "s3:GetBucketIntelligentTieringConfiguration"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ce:GetCostAndUsage",
          "ce:GetCostForecast"
        ]
        Resource = "*"
      }
    ]
  })
}

# Cost allocation tags
resource "aws_ce_cost_allocation_tag" "storage_tags" {
  for_each = toset(["Environment", "Project", "StorageType", "CompressionEnabled", "LifecycleEnabled"])

  tag_key = each.key
  status  = "Active"
}

# Data source for region
data "aws_region" "current" {}

# Outputs
output "alerts" {
  description = "Cost monitoring alerts configuration"
  value = {
    sns_topic_arn = aws_sns_topic.cost_alerts.arn
    s3_budget = {
      name   = aws_budgets_budget.s3_storage.name
      amount = aws_budgets_budget.s3_storage.limit_amount
    }
    logs_budget = {
      name   = aws_budgets_budget.cloudwatch_logs.name
      amount = aws_budgets_budget.cloudwatch_logs.limit_amount
    }
    anomaly_detector = aws_ce_anomaly_monitor.storage_costs.name
  }
}

output "dashboard_url" {
  description = "CloudWatch dashboard URL"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.storage_costs.dashboard_name}"
}

output "cost_calculator_function" {
  description = "Cost calculator Lambda function"
  value       = aws_lambda_function.cost_calculator.function_name
}