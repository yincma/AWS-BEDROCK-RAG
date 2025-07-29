# CloudWatch Logs Optimization for Cost Reduction

# Default retention periods by environment
locals {
  default_retention_days = {
    dev     = 7
    staging = 30
    prod    = 90
  }

  # Calculate storage cost per GB per month
  logs_storage_cost_per_gb   = 0.03
  logs_ingestion_cost_per_gb = 0.50
}

# Optimized log groups with retention policies
resource "aws_cloudwatch_log_group" "optimized" {
  for_each = var.log_groups

  name = each.key
  retention_in_days = coalesce(
    each.value.retention_in_days,
    local.default_retention_days[var.environment]
  )
  kms_key_id = each.value.kms_key_id

  tags = merge(
    var.common_tags,
    {
      Name               = each.key
      Environment        = var.environment
      RetentionDays      = coalesce(each.value.retention_in_days, local.default_retention_days[var.environment])
      CompressionEnabled = each.value.enable_compression
    }
  )
}

# Critical metric filters only (reduce costs)
resource "aws_cloudwatch_log_metric_filter" "critical_only" {
  for_each = var.enable_metric_filters ? local.critical_metrics : {}

  name           = each.key
  log_group_name = each.value.log_group
  pattern        = each.value.pattern

  metric_transformation {
    name          = each.value.metric_name
    namespace     = "${var.project_name}/${var.environment}"
    value         = each.value.value
    default_value = each.value.default_value
    unit          = each.value.unit
  }

  depends_on = [aws_cloudwatch_log_group.optimized]
}

# Subscription filters with sampling for cost reduction
resource "aws_cloudwatch_log_subscription_filter" "sampled" {
  for_each = {
    for k, v in var.log_groups : k => v
    if var.enable_subscription_filters && v.subscription_filter != null
  }

  name            = "${each.key}-subscription"
  log_group_name  = aws_cloudwatch_log_group.optimized[each.key].name
  filter_pattern  = each.value.subscription_filter.filter_pattern
  destination_arn = each.value.subscription_filter.destination_arn

  # Enable sampling for high-volume logs
  distribution = each.value.enable_sampling ? "Random" : "ByLogStream"

  depends_on = [aws_cloudwatch_log_group.optimized]
}

# Lambda function for log compression and archival
resource "aws_lambda_function" "log_compressor" {
  count = length([for k, v in var.log_groups : k if v.enable_compression]) > 0 ? 1 : 0

  filename      = data.archive_file.log_compressor[0].output_path
  function_name = "${var.project_name}-${var.environment}-log-compressor"
  role          = aws_iam_role.log_compressor[0].arn
  handler       = "index.handler"
  runtime       = "python3.9"
  timeout       = 300
  memory_size   = 512

  environment {
    variables = {
      ARCHIVE_BUCKET    = aws_s3_bucket.log_archive[0].id
      COMPRESSION_LEVEL = "9"
      DELETE_AFTER_DAYS = "7"
    }
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-log-compressor"
      Type = "Cost-Optimization"
    }
  )
}

# Log archive S3 bucket
resource "aws_s3_bucket" "log_archive" {
  count = length([for k, v in var.log_groups : k if v.enable_compression]) > 0 ? 1 : 0

  bucket = "${var.project_name}-${var.environment}-log-archive-${data.aws_caller_identity.current.account_id}"

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-log-archive"
      Type = "Log-Archive"
    }
  )
}

# Lifecycle for archived logs
resource "aws_s3_bucket_lifecycle_configuration" "log_archive" {
  count  = length(aws_s3_bucket.log_archive) > 0 ? 1 : 0
  bucket = aws_s3_bucket.log_archive[0].id

  rule {
    id     = "archive-lifecycle"
    status = "Enabled"

    filter {}

    transition {
      days          = 1
      storage_class = "GLACIER"
    }

    transition {
      days          = 90
      storage_class = "DEEP_ARCHIVE"
    }

    expiration {
      days = 365
    }
  }
}

# EventBridge rule for scheduled log exports
resource "aws_cloudwatch_event_rule" "log_export_schedule" {
  count = length([for k, v in var.log_groups : k if v.enable_compression]) > 0 ? 1 : 0

  name                = "${var.project_name}-${var.environment}-log-export"
  description         = "Scheduled log export for cost optimization"
  schedule_expression = "rate(1 day)"

  tags = var.common_tags
}

resource "aws_cloudwatch_event_target" "log_export_target" {
  count = length(aws_cloudwatch_event_rule.log_export_schedule) > 0 ? 1 : 0

  rule      = aws_cloudwatch_event_rule.log_export_schedule[0].name
  target_id = "LogExportLambda"
  arn       = aws_lambda_function.log_compressor[0].arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  count = length(aws_lambda_function.log_compressor) > 0 ? 1 : 0

  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.log_compressor[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.log_export_schedule[0].arn
}

# Lambda function code
data "archive_file" "log_compressor" {
  count = length([for k, v in var.log_groups : k if v.enable_compression]) > 0 ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/log-compressor.zip"

  source {
    content  = file("${path.module}/log-compressor.py")
    filename = "index.py"
  }
}

# IAM role for log compressor
resource "aws_iam_role" "log_compressor" {
  count = length([for k, v in var.log_groups : k if v.enable_compression]) > 0 ? 1 : 0

  name = "${var.project_name}-${var.environment}-log-compressor-role"

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

# IAM policy for log compressor
resource "aws_iam_role_policy" "log_compressor" {
  count = length(aws_iam_role.log_compressor) > 0 ? 1 : 0

  name = "log-compressor-policy"
  role = aws_iam_role.log_compressor[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:FilterLogEvents",
          "logs:CreateExportTask",
          "logs:DescribeExportTasks"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.log_archive[0].arn}/*"
      }
    ]
  })
}

# Cost-saving metric aggregation
resource "aws_cloudwatch_composite_alarm" "log_costs" {
  alarm_name        = "${var.project_name}-${var.environment}-high-log-costs"
  alarm_description = "Alert when log costs are high"
  actions_enabled   = true

  alarm_rule = join(" OR ", [
    for k, v in var.log_groups :
    "ALARM(\"${k}-size-alarm\")"
  ])

  tags = var.common_tags
}

# Log group size alarms
resource "aws_cloudwatch_metric_alarm" "log_group_size" {
  for_each = var.log_groups

  alarm_name          = "${each.key}-size-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "IncomingBytes"
  namespace           = "AWS/Logs"
  period              = "86400" # Daily
  statistic           = "Sum"
  threshold           = 5368709120 # 5 GB
  alarm_description   = "Log group ${each.key} exceeds 5GB daily ingestion"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LogGroupName = aws_cloudwatch_log_group.optimized[each.key].name
  }

  tags = var.common_tags
}

# Data source for account ID
data "aws_caller_identity" "current" {}

# Critical metrics definition
locals {
  critical_metrics = {
    errors = {
      log_group     = try(var.log_groups["application-logs"].name, "/aws/lambda/default")
      pattern       = "[ERROR]"
      metric_name   = "ErrorCount"
      value         = "1"
      default_value = "0"
      unit          = "Count"
    }
    latency = {
      log_group     = try(var.log_groups["api-logs"].name, "/aws/apigateway/default")
      pattern       = "[LATENCY > 1000]"
      metric_name   = "HighLatency"
      value         = "1"
      default_value = "0"
      unit          = "Count"
    }
  }

  # Calculate estimated savings
  total_retention_reduction = sum([
    for k, v in var.log_groups :
    (90 - coalesce(v.retention_in_days, local.default_retention_days[var.environment])) / 90
  ])

  compression_savings = sum([
    for k, v in var.log_groups :
    v.enable_compression ? 0.7 : 0 # 70% compression ratio
  ])

  estimated_monthly_savings = (
    (local.total_retention_reduction * 100 * local.logs_storage_cost_per_gb) +
    (local.compression_savings * 50 * local.logs_storage_cost_per_gb)
  )
}

# Outputs
output "log_group_configurations" {
  description = "Optimized log group configurations"
  value = {
    for k, v in aws_cloudwatch_log_group.optimized :
    k => {
      name           = v.name
      retention_days = v.retention_in_days
      kms_encrypted  = v.kms_key_id != null
    }
  }
}

output "optimized_log_groups_count" {
  description = "Number of optimized log groups"
  value       = length(aws_cloudwatch_log_group.optimized)
}

output "compression_enabled_count" {
  description = "Number of log groups with compression enabled"
  value       = length([for k, v in var.log_groups : k if v.enable_compression])
}

output "log_archive_bucket" {
  description = "S3 bucket for archived logs"
  value       = try(aws_s3_bucket.log_archive[0].id, null)
}

output "estimated_monthly_savings" {
  description = "Estimated monthly savings from log optimization"
  value       = local.estimated_monthly_savings
}