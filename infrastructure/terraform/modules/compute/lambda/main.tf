# Lambda函数模块

# 死信队列
resource "aws_sqs_queue" "dlq" {
  count = var.enable_dlq ? 1 : 0

  name                      = "${var.function_name}-dlq"
  message_retention_seconds = 1209600 # 14天

  tags = merge(var.common_tags, {
    Name = "${var.function_name}-dlq"
    Type = "SQS Queue"
  })
}

# CloudWatch日志组 - 由监控模块统一管理
# resource "aws_cloudwatch_log_group" "lambda" {
#   name              = "/aws/lambda/${var.function_name}"
#   retention_in_days = var.log_retention_days
#   
#   tags = merge(var.common_tags, {
#     Name = "${var.function_name}-logs"
#     Type = "CloudWatch Logs"
#   })
# }

# Lambda函数
resource "aws_lambda_function" "function" {
  function_name = var.function_name
  role          = var.execution_role_arn
  handler       = var.handler
  runtime       = var.runtime
  timeout       = var.timeout
  memory_size   = var.memory_size

  # 代码配置
  filename         = var.deployment_package_path
  source_code_hash = var.deployment_package_path != null ? filebase64sha256(var.deployment_package_path) : null

  # 环境变量
  environment {
    variables = var.environment_variables
  }

  # VPC配置
  dynamic "vpc_config" {
    for_each = length(var.subnet_ids) > 0 ? [1] : []
    content {
      subnet_ids         = var.subnet_ids
      security_group_ids = var.security_group_ids
    }
  }

  # Lambda层
  layers = var.layers

  # 死信队列配置
  dynamic "dead_letter_config" {
    for_each = var.enable_dlq ? [1] : []
    content {
      target_arn = aws_sqs_queue.dlq[0].arn
    }
  }

  # 预留并发
  reserved_concurrent_executions = var.reserved_concurrent_executions

  # X-Ray追踪
  dynamic "tracing_config" {
    for_each = var.enable_xray ? [1] : []
    content {
      mode = "Active"
    }
  }

  # 架构
  architectures = [var.architecture]

  tags = merge(var.common_tags, {
    Name        = var.function_name
    Type        = "Lambda Function"
    Environment = var.environment
  })
}

# Lambda别名（用于蓝绿部署）
resource "aws_lambda_alias" "live" {
  count = var.enable_alias ? 1 : 0

  name             = "live"
  description      = "Live alias for ${var.function_name}"
  function_name    = aws_lambda_function.function.function_name
  function_version = aws_lambda_function.function.version
}

# Lambda函数URL（可选）
resource "aws_lambda_function_url" "function_url" {
  count = var.enable_function_url ? 1 : 0

  function_name      = aws_lambda_function.function.function_name
  authorization_type = var.function_url_auth_type

  cors {
    allow_credentials = var.function_url_cors.allow_credentials
    allow_origins     = var.function_url_cors.allow_origins
    allow_methods     = var.function_url_cors.allow_methods
    allow_headers     = var.function_url_cors.allow_headers
    expose_headers    = var.function_url_cors.expose_headers
    max_age           = var.function_url_cors.max_age
  }
}

# CloudWatch警报 - 错误率
resource "aws_cloudwatch_metric_alarm" "error_rate" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.function_name}-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.error_threshold
  alarm_description   = "Lambda函数错误率过高"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.function.function_name
  }

  alarm_actions = var.alarm_sns_topic_arns

  tags = merge(var.common_tags, {
    Name = "${var.function_name}-error-alarm"
    Type = "CloudWatch Alarm"
  })
}

# CloudWatch警报 - 执行时间
resource "aws_cloudwatch_metric_alarm" "duration" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.function_name}-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = var.duration_threshold
  alarm_description   = "Lambda函数执行时间过长"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.function.function_name
  }

  alarm_actions = var.alarm_sns_topic_arns

  tags = merge(var.common_tags, {
    Name = "${var.function_name}-duration-alarm"
    Type = "CloudWatch Alarm"
  })
}

# CloudWatch警报 - 并发执行
resource "aws_cloudwatch_metric_alarm" "concurrent_executions" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.function_name}-concurrent-executions"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ConcurrentExecutions"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Maximum"
  threshold           = var.concurrent_executions_threshold
  alarm_description   = "Lambda函数并发执行数过高"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.function.function_name
  }

  alarm_actions = var.alarm_sns_topic_arns

  tags = merge(var.common_tags, {
    Name = "${var.function_name}-concurrency-alarm"
    Type = "CloudWatch Alarm"
  })
}