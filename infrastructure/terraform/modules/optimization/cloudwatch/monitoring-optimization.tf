# CloudWatch Monitoring Optimization Module
# 优化监控成本，实现日志聚合、指标精简和采样策略

# 日志组优化配置
resource "aws_cloudwatch_log_group" "optimized" {
  for_each = var.log_groups

  name              = each.value.name
  retention_in_days = each.value.retention_days
  kms_key_id        = var.kms_key_id

  tags = merge(
    var.tags,
    {
      CostOptimized = "true"
      RetentionDays = each.value.retention_days
    }
  )
}

# 日志指标过滤器 - 减少不必要的指标
resource "aws_cloudwatch_log_metric_filter" "optimized_metrics" {
  for_each = var.metric_filters

  name           = each.key
  log_group_name = each.value.log_group_name
  pattern        = each.value.pattern

  metric_transformation {
    name          = each.value.metric_name
    namespace     = each.value.namespace
    value         = each.value.value
    default_value = each.value.default_value
    dimensions    = each.value.dimensions
    unit          = each.value.unit
  }
}

# 日志采样Lambda函数
resource "aws_lambda_function" "log_sampler" {
  function_name = "${var.environment}-log-sampler"
  description   = "Sample logs to reduce CloudWatch costs"
  role          = aws_iam_role.log_sampler.arn
  handler       = "sampler.handler"
  runtime       = "python3.9"
  timeout       = 60
  memory_size   = 512

  environment {
    variables = {
      SAMPLING_RATE     = var.sampling_rate
      SAMPLING_RULES    = jsonencode(var.sampling_rules)
      DESTINATION_GROUP = var.sampled_logs_group
    }
  }

  filename         = data.archive_file.log_sampler.output_path
  source_code_hash = data.archive_file.log_sampler.output_base64sha256

  reserved_concurrent_executions = 5

  tags = var.tags
}

# 日志采样IAM角色
resource "aws_iam_role" "log_sampler" {
  name = "${var.environment}-log-sampler-role"

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

  tags = var.tags
}

resource "aws_iam_role_policy" "log_sampler" {
  name = "log-sampler-policy"
  role = aws_iam_role.log_sampler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

# 日志聚合Kinesis Firehose
resource "aws_kinesis_firehose_delivery_stream" "log_aggregator" {
  name        = "${var.environment}-log-aggregator"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = aws_iam_role.firehose.arn
    bucket_arn          = var.log_archive_bucket_arn
    prefix              = "aggregated-logs/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "error-logs/"

    # 压缩配置
    compression_format = "GZIP"

    # 缓冲配置 - 平衡成本和实时性
    buffer_size     = 5   # 5MB
    buffer_interval = 300 # 5分钟

    # 数据处理配置
    processing_configuration {
      enabled = "true"

      processors {
        type = "Lambda"

        parameters {
          parameter_name  = "LambdaArn"
          parameter_value = aws_lambda_function.log_processor.arn
        }
      }
    }

    # 数据格式转换（转换为Parquet以进一步减少存储）
    data_format_conversion_configuration {
      enabled = true

      output_format_configuration {
        serializer {
          parquet_ser_de {}
        }
      }

      input_format_configuration {
        deserializer {
          open_x_json_ser_de {}
        }
      }

      schema_configuration {
        database_name = var.glue_database_name
        table_name    = var.glue_table_name
      }
    }
  }

  tags = var.tags
}

# 日志处理Lambda
resource "aws_lambda_function" "log_processor" {
  function_name = "${var.environment}-log-processor"
  description   = "Process and filter logs before storage"
  role          = aws_iam_role.log_processor.arn
  handler       = "processor.handler"
  runtime       = "python3.9"
  timeout       = 180
  memory_size   = 1024

  environment {
    variables = {
      FILTER_RULES         = jsonencode(var.log_filter_rules)
      ENABLE_DEDUPLICATION = var.enable_log_deduplication
    }
  }

  filename         = data.archive_file.log_processor.output_path
  source_code_hash = data.archive_file.log_processor.output_base64sha256

  tags = var.tags
}

# Firehose IAM角色
resource "aws_iam_role" "firehose" {
  name = "${var.environment}-firehose-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "firehose" {
  name = "firehose-policy"
  role = aws_iam_role.firehose.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]
        Resource = [
          var.log_archive_bucket_arn,
          "${var.log_archive_bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = aws_lambda_function.log_processor.arn
      },
      {
        Effect = "Allow"
        Action = [
          "glue:GetTable",
          "glue:GetTableVersion"
        ]
        Resource = "*"
      }
    ]
  })
}

# Log Processor IAM角色
resource "aws_iam_role" "log_processor" {
  name = "${var.environment}-log-processor-role"

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

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "log_processor_basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.log_processor.name
}

# 指标精简配置
resource "aws_cloudwatch_metric_stream" "cost_optimized" {
  name          = "${var.environment}-cost-optimized-metrics"
  role_arn      = aws_iam_role.metric_stream.arn
  firehose_arn  = aws_kinesis_firehose_delivery_stream.metric_aggregator.arn
  output_format = "json"

  # 包含关键指标
  dynamic "include_filter" {
    for_each = var.essential_metrics
    content {
      namespace = include_filter.value
    }
  }

  # 排除高成本低价值指标
  dynamic "exclude_filter" {
    for_each = var.excluded_metrics
    content {
      namespace    = exclude_filter.value.namespace
      metric_names = exclude_filter.value.metric_names
    }
  }

  tags = var.tags
}

# 指标聚合Firehose
resource "aws_kinesis_firehose_delivery_stream" "metric_aggregator" {
  name        = "${var.environment}-metric-aggregator"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = aws_iam_role.firehose.arn
    bucket_arn          = var.metric_archive_bucket_arn
    prefix              = "metrics/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "metric-errors/"
    compression_format  = "GZIP"
    buffer_size         = 5
    buffer_interval     = 60 # 1分钟聚合
  }

  tags = var.tags
}

# Metric Stream IAM角色
resource "aws_iam_role" "metric_stream" {
  name = "${var.environment}-metric-stream-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "streams.metrics.cloudwatch.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "metric_stream" {
  name = "metric-stream-policy"
  role = aws_iam_role.metric_stream.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "firehose:PutRecord",
          "firehose:PutRecordBatch"
        ]
        Resource = aws_kinesis_firehose_delivery_stream.metric_aggregator.arn
      }
    ]
  })
}

# 成本告警配置
resource "aws_cloudwatch_metric_alarm" "monitoring_cost_alarm" {
  for_each = var.cost_alarms

  alarm_name          = each.key
  comparison_operator = each.value.comparison_operator
  evaluation_periods  = each.value.evaluation_periods
  threshold           = each.value.threshold
  alarm_description   = each.value.description
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "cost"
    return_data = true

    metric {
      metric_name = "EstimatedCharges"
      namespace   = "AWS/Billing"
      period      = 86400 # Daily
      stat        = "Maximum"

      dimensions = {
        Currency      = "USD"
        LinkedAccount = each.value.account_id
      }
    }
  }

  alarm_actions = each.value.alarm_actions
  ok_actions    = each.value.ok_actions

  tags = var.tags
}

# 成本优化仪表板
resource "aws_cloudwatch_dashboard" "monitoring_cost_optimization" {
  dashboard_name = "${var.environment}-monitoring-cost-optimization"

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
            ["AWS/Logs", "IncomingBytes", { stat = "Sum", period = 3600 }],
            [".", "IncomingLogEvents", ".", { stat = "Sum", period = 3600 }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Log Ingestion Volume"
          period  = 300
          yAxis = {
            left = {
              label = "Bytes/Events"
            }
          }
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
            ["AWS/Billing", "EstimatedCharges", "Currency", "USD", "LinkedAccount", data.aws_caller_identity.current.account_id, { stat = "Maximum" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = "us-east-1" # Billing metrics are in us-east-1
          title   = "Estimated CloudWatch Charges"
          period  = 86400
          annotations = {
            horizontal = [
              {
                label = "Budget Limit"
                value = var.monthly_budget_limit
              }
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          metrics = [
            [{ expression = "SEARCH(' MetricName=\"CallCount\" ', 'Sum', 3600)" }]
          ]
          view   = "table"
          region = data.aws_region.current.name
          title  = "API Call Volume by Service"
          period = 3600
        }
      }
    ]
  })
}

# Lambda代码打包
data "archive_file" "log_sampler" {
  type        = "zip"
  source_file = "${path.module}/lambda/sampler.py"
  output_path = "${path.module}/lambda/sampler.zip"
}

data "archive_file" "log_processor" {
  type        = "zip"
  source_file = "${path.module}/lambda/processor.py"
  output_path = "${path.module}/lambda/processor.zip"
}

# 数据源
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# 输出
output "monitoring_optimization_config" {
  value = {
    log_retention_days = {
      for k, v in var.log_groups : k => v.retention_days
    }
    sampling_rate                = var.sampling_rate
    metric_filters_count         = length(var.metric_filters)
    excluded_metrics_count       = length(var.excluded_metrics)
    cost_alarms_count            = length(var.cost_alarms)
    estimated_savings_percentage = 40 # Target savings
  }
  description = "Monitoring optimization configuration"
}

# 变量定义
variable "environment" {
  description = "Environment name"
  type        = string
}

variable "log_groups" {
  description = "Optimized log group configurations"
  type = map(object({
    name           = string
    retention_days = number
  }))
  default = {}
}

variable "metric_filters" {
  description = "Optimized metric filters"
  type = map(object({
    log_group_name = string
    pattern        = string
    metric_name    = string
    namespace      = string
    value          = string
    default_value  = string
    dimensions     = map(string)
    unit           = string
  }))
  default = {}
}

variable "sampling_rate" {
  description = "Default log sampling rate (0-1)"
  type        = number
  default     = 0.1 # 10% sampling
}

variable "sampling_rules" {
  description = "Custom sampling rules by log level or pattern"
  type = map(object({
    pattern = string
    rate    = number
  }))
  default = {
    error = {
      pattern = "ERROR"
      rate    = 1.0 # Keep all errors
    }
    warning = {
      pattern = "WARN"
      rate    = 0.5 # Keep 50% of warnings
    }
    info = {
      pattern = "INFO"
      rate    = 0.1 # Keep 10% of info logs
    }
  }
}

variable "sampled_logs_group" {
  description = "Destination log group for sampled logs"
  type        = string
  default     = "/aws/lambda/sampled"
}

variable "log_archive_bucket_arn" {
  description = "S3 bucket ARN for log archives"
  type        = string
}

variable "metric_archive_bucket_arn" {
  description = "S3 bucket ARN for metric archives"
  type        = string
}

variable "log_filter_rules" {
  description = "Rules for filtering logs before storage"
  type = list(object({
    field    = string
    operator = string
    value    = string
    action   = string
  }))
  default = []
}

variable "enable_log_deduplication" {
  description = "Enable log deduplication"
  type        = bool
  default     = true
}

variable "glue_database_name" {
  description = "Glue database for log schema"
  type        = string
  default     = "cloudwatch_logs"
}

variable "glue_table_name" {
  description = "Glue table for log schema"
  type        = string
  default     = "aggregated_logs"
}

variable "essential_metrics" {
  description = "Essential metric namespaces to keep"
  type        = list(string)
  default = [
    "AWS/Lambda",
    "AWS/ApiGateway",
    "AWS/S3",
    "AWS/DynamoDB",
    "AWS/RDS"
  ]
}

variable "excluded_metrics" {
  description = "Metrics to exclude for cost optimization"
  type = list(object({
    namespace    = string
    metric_names = list(string)
  }))
  default = []
}

variable "cost_alarms" {
  description = "Cost alarm configurations"
  type = map(object({
    comparison_operator = string
    evaluation_periods  = number
    threshold           = number
    description         = string
    account_id          = string
    alarm_actions       = list(string)
    ok_actions          = list(string)
  }))
  default = {}
}

variable "monthly_budget_limit" {
  description = "Monthly budget limit for monitoring costs"
  type        = number
  default     = 100
}

variable "kms_key_id" {
  description = "KMS key ID for encryption"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}