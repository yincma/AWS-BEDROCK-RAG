# Lambda Performance Optimization Module
# 实现预留并发、内存优化、冷启动减少和性能监控

# 预留并发配置
resource "aws_lambda_reserved_concurrent_executions" "optimized" {
  for_each = var.lambda_performance_config

  function_name                  = each.key
  reserved_concurrent_executions = each.value.reserved_concurrent_executions
}

# 预配置并发（减少冷启动）
resource "aws_lambda_provisioned_concurrency_config" "optimized" {
  for_each = {
    for k, v in var.lambda_performance_config : k => v
    if v.provisioned_concurrent_executions > 0
  }

  function_name                     = each.key
  provisioned_concurrent_executions = each.value.provisioned_concurrent_executions
  qualifier                         = each.value.alias_name
}

# Lambda 函数配置优化
resource "aws_lambda_function_configuration" "optimized" {
  for_each = var.lambda_performance_config

  function_name = each.key

  # 内存优化配置
  memory_size = each.value.optimized_memory_size

  # 架构优化（ARM64 更便宜且性能更好）
  architectures = [each.value.architecture]

  # 临时存储配置
  ephemeral_storage {
    size = each.value.ephemeral_storage_size
  }

  # SnapStart 配置（Java 函数冷启动优化）
  dynamic "snap_start" {
    for_each = each.value.enable_snap_start ? [1] : []
    content {
      apply_on = "PublishedVersions"
    }
  }
}

# CloudWatch 性能指标
resource "aws_cloudwatch_metric_alarm" "lambda_cold_start" {
  for_each = var.lambda_performance_config

  alarm_name          = "${each.key}-cold-start-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "InitDuration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = each.value.cold_start_threshold_ms
  alarm_description   = "Lambda function ${each.key} cold start time exceeds threshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = each.key
  }

  alarm_actions = var.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  for_each = var.lambda_performance_config

  alarm_name          = "${each.key}-duration-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = each.value.duration_threshold_ms
  alarm_description   = "Lambda function ${each.key} duration exceeds threshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = each.key
  }

  alarm_actions = var.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = var.lambda_performance_config

  alarm_name          = "${each.key}-error-rate-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = each.value.error_threshold
  alarm_description   = "Lambda function ${each.key} error rate exceeds threshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = each.key
  }

  alarm_actions = var.alarm_actions
}

# X-Ray 追踪配置
resource "aws_xray_sampling_rule" "lambda_performance" {
  count = var.enable_xray_tracing ? 1 : 0

  rule_name      = "lambda-performance-sampling"
  priority       = 1000
  version        = 1
  reservoir_size = 1
  fixed_rate     = 0.1
  url_path       = "*"
  host           = "*"
  http_method    = "*"
  service_type   = "AWS::Lambda::Function"
  service_name   = "*"
  resource_arn   = "*"
}

# Lambda Insights 配置
resource "aws_lambda_layer_version" "lambda_insights" {
  count = var.enable_lambda_insights ? 1 : 0

  layer_name          = "lambda-insights-extension"
  description         = "Lambda Insights extension layer"
  s3_bucket           = "amazon-lambda-insights-${data.aws_region.current.name}"
  s3_key              = "lambda-insights-extension.zip"
  compatible_runtimes = ["python3.8", "python3.9", "python3.10", "nodejs14.x", "nodejs16.x", "nodejs18.x"]
}

# Performance Dashboard
resource "aws_cloudwatch_dashboard" "lambda_performance" {
  dashboard_name = "lambda-performance-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            for fn, config in var.lambda_performance_config : [
              "AWS/Lambda", "Duration", { stat = "Average", label = "${fn} Avg Duration" },
              ".", ".", { stat = "p99", label = "${fn} P99 Duration" }
            ]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Lambda Function Duration"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            for fn, config in var.lambda_performance_config : [
              "AWS/Lambda", "ConcurrentExecutions", "FunctionName", fn
            ]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Concurrent Executions"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            for fn, config in var.lambda_performance_config : [
              "AWS/Lambda", "InitDuration", "FunctionName", fn, { stat = "Average" }
            ]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Cold Start Duration"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            for fn, config in var.lambda_performance_config : [
              "AWS/Lambda", "Errors", "FunctionName", fn, { stat = "Sum" },
              ".", "Throttles", ".", ".", { stat = "Sum" }
            ]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Errors and Throttles"
          period  = 300
        }
      }
    ]
  })
}

# 输出性能优化结果
output "lambda_performance_optimizations" {
  value = {
    for fn, config in var.lambda_performance_config : fn => {
      reserved_concurrency    = config.reserved_concurrent_executions
      provisioned_concurrency = config.provisioned_concurrent_executions
      memory_size             = config.optimized_memory_size
      architecture            = config.architecture
      cold_start_reduction    = config.provisioned_concurrent_executions > 0 ? "Enabled" : "Disabled"
      performance_monitoring  = "Enabled"
    }
  }
  description = "Lambda performance optimization configurations"
}

# 数据源
data "aws_region" "current" {}

# 变量定义
variable "lambda_performance_config" {
  description = "Lambda performance optimization configuration"
  type = map(object({
    reserved_concurrent_executions    = number
    provisioned_concurrent_executions = number
    optimized_memory_size             = number
    architecture                      = string
    ephemeral_storage_size            = number
    enable_snap_start                 = bool
    alias_name                        = string
    cold_start_threshold_ms           = number
    duration_threshold_ms             = number
    error_threshold                   = number
  }))
  default = {}
}

variable "enable_xray_tracing" {
  description = "Enable X-Ray tracing for performance monitoring"
  type        = bool
  default     = true
}

variable "enable_lambda_insights" {
  description = "Enable Lambda Insights for enhanced monitoring"
  type        = bool
  default     = true
}

variable "alarm_actions" {
  description = "List of ARNs to notify when alarms trigger"
  type        = list(string)
  default     = []
}