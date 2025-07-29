# 监控模块 - CloudWatch Dashboard、告警、日志聚合等

# SNS主题 - 告警通知
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts-${var.environment}"

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-alerts-${var.environment}"
    Type = "Monitoring"
  })
}

# SNS主题订阅 - Email
resource "aws_sns_topic_subscription" "alert_email" {
  count     = var.alarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-dashboard-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      # API Gateway 性能指标
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiName", var.api_gateway_name, "Stage", var.api_gateway_stage, { stat = "Sum", label = "请求总数" }],
            [".", "Latency", ".", ".", ".", ".", { stat = "Average", label = "平均延迟(ms)" }],
            [".", "4XXError", ".", ".", ".", ".", { stat = "Sum", label = "4XX错误", color = "#ff7f0e" }],
            [".", "5XXError", ".", ".", ".", ".", { stat = "Sum", label = "5XX错误", color = "#d62728" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "API Gateway 性能指标"
          period  = 300
          yAxis = {
            left  = { min = 0 }
            right = { min = 0 }
          }
          annotations = {
            horizontal = [
              {
                label = "延迟阈值"
                value = 3000
              }
            ]
          }
        }
      },

      # Lambda 函数性能
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = concat(
            [for fn in var.lambda_functions :
              ["AWS/Lambda", "Duration", "FunctionName", fn, {
                stat  = "Average",
                label = fn
              }]
            ],
            [for fn in var.lambda_functions :
              [".", "Errors", ".", fn, {
                stat  = "Sum",
                label = "${fn} Errors",
                yAxis = "right"
              }]
            ]
          )
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Lambda 函数性能"
          period  = 300
          yAxis = {
            left = {
              label = "执行时间 (ms)"
              min   = 0
            }
            right = {
              label = "错误数"
              min   = 0
            }
          }
        }
      },

      # Bedrock 使用情况
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["RAG-System/QueryHandler", "BedrockRequests", { stat = "Sum", label = "Bedrock请求数" }],
            [".", "BedrockLatency", { stat = "Average", label = "Bedrock延迟(ms)" }],
            [".", "BedrockErrors", { stat = "Sum", label = "Bedrock错误", color = "#d62728" }],
            [".", "TokensUsed", { stat = "Sum", label = "Token使用量", yAxis = "right" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Bedrock AI 服务使用情况"
          period  = 300
        }
      },

      # 错误率热图
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            for fn in var.lambda_functions :
            ["AWS/Lambda", "Errors", "FunctionName", fn, {
              stat = "Sum"
            }]
          ]
          view   = "heatmap"
          region = var.aws_region
          title  = "Lambda 错误热图"
          period = 300
          yAxis = {
            left = { min = 0 }
          }
        }
      },

      # 并发执行监控
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 8
        height = 6

        properties = {
          metrics = [
            ["AWS/Lambda", "ConcurrentExecutions", { stat = "Maximum", label = "最大并发" }],
            [".", "UnreservedConcurrentExecutions", { stat = "Maximum", label = "未预留并发" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Lambda 并发执行"
          period  = 60
          annotations = {
            horizontal = [
              {
                label = "并发限制"
                value = 1000
              }
            ]
          }
        }
      },

      # 成本监控
      {
        type   = "metric"
        x      = 8
        y      = 12
        width  = 8
        height = 6

        properties = {
          metrics = [
            ["AWS/Billing", "EstimatedCharges", "Currency", "USD", {
              stat  = "Maximum",
              label = "预估费用 (USD)"
            }]
          ]
          view   = "singleValue"
          region = "us-east-1" # Billing metrics only in us-east-1
          title  = "当月预估费用"
          period = 86400 # 24小时
        }
      },

      # 系统健康度
      {
        type   = "metric"
        x      = 16
        y      = 12
        width  = 8
        height = 6

        properties = {
          metrics = [
            ["RAG-System/Health", "SystemAvailability", { stat = "Average", label = "系统可用性 %" }],
            [".", "HealthChecksPassed", { stat = "Sum", label = "健康检查通过", yAxis = "right" }],
            [".", "HealthChecksFailed", { stat = "Sum", label = "健康检查失败", yAxis = "right", color = "#d62728" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "系统健康状态"
          period  = 300
        }
      },

      # 日志洞察查询
      {
        type   = "log"
        x      = 0
        y      = 18
        width  = 24
        height = 6

        properties = {
          query     = <<-EOT
            SOURCE '/aws/lambda/${var.project_name}-query-handler-${var.environment}'
            | fields @timestamp, @message
            | filter @message like /ERROR/
            | sort @timestamp desc
            | limit 20
          EOT
          region    = var.aws_region
          title     = "最近的错误日志"
          queryType = "Logs"
        }
      },

      # 自定义指标 - 查询分析
      {
        type   = "metric"
        x      = 0
        y      = 24
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["RAG-System/Analytics", "QueryComplexity", { stat = "Average", label = "查询复杂度" }],
            [".", "ResponseRelevance", { stat = "Average", label = "响应相关性评分" }],
            [".", "UserSatisfaction", { stat = "Average", label = "用户满意度", yAxis = "right" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "查询质量分析"
          period  = 3600 # 1小时
          yAxis = {
            left  = { min = 0, max = 100 }
            right = { min = 0, max = 5 }
          }
        }
      },

      # 文档处理监控
      {
        type   = "metric"
        x      = 12
        y      = 24
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["RAG-System/DocumentProcessor", "DocumentsProcessed", { stat = "Sum", label = "处理的文档数" }],
            [".", "ProcessingTime", { stat = "Average", label = "平均处理时间(s)" }],
            [".", "ProcessingErrors", { stat = "Sum", label = "处理错误", color = "#d62728" }],
            [".", "DocumentSize", { stat = "Average", label = "平均文档大小(MB)", yAxis = "right" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "文档处理监控"
          period  = 300
        }
      }
    ]
  })
}

# CloudWatch 告警 - API Gateway 高错误率
resource "aws_cloudwatch_metric_alarm" "api_high_error_rate" {
  alarm_name          = "${var.project_name}-api-high-error-rate-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "4XXError"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Sum"
  threshold           = "50"
  alarm_description   = "API Gateway 4XX错误率过高"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiName = var.api_gateway_name
    Stage   = var.api_gateway_stage
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-api-error-alarm-${var.environment}"
    Type = "Alarm"
  })
}

# CloudWatch 告警 - API Gateway 高延迟
resource "aws_cloudwatch_metric_alarm" "api_high_latency" {
  alarm_name          = "${var.project_name}-api-high-latency-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "Latency"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Average"
  threshold           = "3000" # 3秒
  alarm_description   = "API Gateway平均延迟超过3秒"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiName = var.api_gateway_name
    Stage   = var.api_gateway_stage
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-api-latency-alarm-${var.environment}"
    Type = "Alarm"
  })
}

# CloudWatch 告警 - Lambda 函数错误
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = toset(var.lambda_functions)

  alarm_name          = "${each.key}-errors-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "${each.key} Lambda函数错误过多"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = each.key
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = merge(var.common_tags, {
    Name = "${each.key}-error-alarm-${var.environment}"
    Type = "Alarm"
  })
}

# CloudWatch 告警 - Lambda 函数持续时间
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  for_each = toset(var.lambda_functions)

  alarm_name          = "${each.key}-duration-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = "30000" # 30秒
  alarm_description   = "${each.key} Lambda函数执行时间过长"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = each.key
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = merge(var.common_tags, {
    Name = "${each.key}-duration-alarm-${var.environment}"
    Type = "Alarm"
  })
}

# CloudWatch 告警 - 成本告警
resource "aws_cloudwatch_metric_alarm" "cost_alert" {
  count = var.cost_alert_threshold > 0 ? 1 : 0

  alarm_name          = "${var.project_name}-cost-alert-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = "86400" # 24小时
  statistic           = "Maximum"
  threshold           = var.cost_alert_threshold
  alarm_description   = "AWS月度费用超过预算阈值"
  treat_missing_data  = "breaching"

  dimensions = {
    Currency = "USD"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-cost-alarm-${var.environment}"
    Type = "Alarm"
  })
}

# CloudWatch日志组 - 纯声明式配置
# 注意：Lambda函数会自动创建日志组，所以这里注释掉避免冲突
# 如果需要管理日志组的保留期等设置，建议：
# 1. 在各个Lambda模块中单独管理其日志组
# 2. 或者先导入现有日志组：terraform import 'module.monitoring.aws_cloudwatch_log_group.lambda_logs["function-name"]' /aws/lambda/function-name

# resource "aws_cloudwatch_log_group" "lambda_logs" {
#   for_each = toset(var.lambda_functions)
#   
#   name              = "/aws/lambda/${each.value}"
#   retention_in_days = 7
#   
#   tags = merge(var.common_tags, {
#     Name = "${each.value}-logs"
#     Type = "CloudWatch Logs"
#   })
# }

# CloudWatch 日志指标过滤器 - Bedrock 请求
resource "aws_cloudwatch_log_metric_filter" "bedrock_requests" {
  name           = "${var.project_name}-bedrock-requests-${var.environment}"
  log_group_name = "/aws/lambda/${var.project_name}-query-handler-${var.environment}"
  pattern        = "[timestamp, requestId, level=\"INFO\", message=\"Knowledge Base查询完成*\"]"

  metric_transformation {
    name      = "BedrockRequests"
    namespace = "RAG-System/QueryHandler"
    value     = "1"
    unit      = "Count"
  }
}

# CloudWatch 日志指标过滤器 - Bedrock 错误
resource "aws_cloudwatch_log_metric_filter" "bedrock_errors" {
  name           = "${var.project_name}-bedrock-errors-${var.environment}"
  log_group_name = "/aws/lambda/${var.project_name}-query-handler-${var.environment}"
  pattern        = "[timestamp, requestId, level=\"ERROR\", message=\"Knowledge Base查询失败*\"]"

  metric_transformation {
    name      = "BedrockErrors"
    namespace = "RAG-System/QueryHandler"
    value     = "1"
    unit      = "Count"
  }
}

# CloudWatch 日志指标过滤器 - 冷启动
resource "aws_cloudwatch_log_metric_filter" "cold_starts" {
  for_each = toset(var.lambda_functions)

  name           = "${each.key}-cold-starts-${var.environment}"
  log_group_name = "/aws/lambda/${each.key}"
  pattern        = "[timestamp, requestId, level, message=\"INIT_START*\"]"

  metric_transformation {
    name      = "ColdStarts"
    namespace = "RAG-System/Performance"
    value     = "1"
    unit      = "Count"
  }
}

# X-Ray采样规则 - 纯声明式解决方案
# 使用确定性命名和Terraform原生功能

resource "aws_xray_sampling_rule" "main" {
  count = var.enable_xray_tracing ? 1 : 0

  # 使用确定性的命名策略
  rule_name      = "${var.project_name}-sampling-${var.environment}"
  priority       = 9000
  version        = 1
  reservoir_size = 1
  fixed_rate     = var.environment == "prod" ? 0.1 : 0.5
  url_path       = "*"
  host           = "*"
  http_method    = "*"
  service_type   = "*"
  service_name   = "*"
  resource_arn   = "*"

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-xray-sampling-${var.environment}"
    Type = "Monitoring"
  })

  lifecycle {
    # 如果规则已存在，Terraform将尝试更新而不是创建
    # 这是声明式模型的正确行为
    create_before_destroy = false
    # 忽略外部变更，防止状态漂移
    ignore_changes = [
      tags["LastModified"],
      tags["CreatedBy"]
    ]
  }
}

# CloudWatch Synthetics 监控（可选）
resource "aws_synthetics_canary" "api_monitor" {
  count = var.enable_synthetics ? 1 : 0

  name                 = "${var.project_name}-api-monitor-${var.environment}"
  artifact_s3_location = "s3://${var.monitoring_bucket}/canary-artifacts/"
  execution_role_arn   = aws_iam_role.synthetics[0].arn
  handler              = "apiCanary.handler"
  zip_file             = data.archive_file.canary_script[0].output_path
  runtime_version      = "syn-nodejs-puppeteer-3.8"

  schedule {
    expression = "rate(5 minutes)"
  }

  run_config {
    timeout_in_seconds = 60
    memory_in_mb       = 960
  }

  success_retention_period = 2
  failure_retention_period = 14

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-canary-${var.environment}"
    Type = "Synthetics"
  })
}

# IAM角色 - Synthetics
resource "aws_iam_role" "synthetics" {
  count = var.enable_synthetics ? 1 : 0

  name = "${var.project_name}-synthetics-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags
}

# Synthetics脚本
data "archive_file" "canary_script" {
  count = var.enable_synthetics ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/canary.zip"

  source {
    content = templatefile("${path.module}/templates/canary.js", {
      api_endpoint = var.api_endpoint
      test_query   = "健康检查测试"
    })
    filename = "nodejs/node_modules/apiCanary.js"
  }
}