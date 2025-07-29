# CloudWatch Cost Optimization Configuration

# Optimized Log Groups with retention policies
resource "aws_cloudwatch_log_group" "application_logs" {
  for_each = var.log_groups

  name              = each.key
  retention_in_days = lookup(each.value, "retention_days", var.default_retention_days[var.environment])
  kms_key_id        = lookup(each.value, "encrypted", false) ? var.kms_key_id : null

  tags = merge(
    var.common_tags,
    {
      Name        = each.key
      Environment = var.environment
      CostCenter  = lookup(each.value, "cost_center", "default")
    }
  )
}

# Log metric filters for critical metrics only
resource "aws_cloudwatch_log_metric_filter" "critical_metrics" {
  for_each = var.critical_log_metrics

  name           = each.key
  log_group_name = each.value.log_group_name
  pattern        = each.value.filter_pattern

  metric_transformation {
    name          = each.value.metric_name
    namespace     = each.value.metric_namespace
    value         = each.value.metric_value
    default_value = lookup(each.value, "default_value", null)
    unit          = lookup(each.value, "unit", "Count")
  }

  depends_on = [aws_cloudwatch_log_group.application_logs]
}

# Composite alarms to reduce alarm count
resource "aws_cloudwatch_composite_alarm" "cost_optimized" {
  for_each = var.composite_alarms

  alarm_name        = each.key
  alarm_description = each.value.description
  actions_enabled   = true
  alarm_actions     = [aws_sns_topic.alarm_topic.arn]
  ok_actions        = [aws_sns_topic.alarm_topic.arn]

  alarm_rule = each.value.alarm_rule

  tags = var.common_tags
}

# SNS topic for consolidated alerts
resource "aws_sns_topic" "alarm_topic" {
  name = "${var.project_name}-${var.environment}-alarms"

  # Enable server-side encryption
  kms_master_key_id = var.kms_key_id

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-alarm-topic"
      Type = "Monitoring-Alerts"
    }
  )
}

# Metric streams for efficient metric export
resource "aws_cloudwatch_metric_stream" "cost_optimized" {
  count = var.enable_metric_stream ? 1 : 0

  name          = "${var.project_name}-${var.environment}-metric-stream"
  role_arn      = aws_iam_role.metric_stream[0].arn
  firehose_arn  = aws_kinesis_firehose_delivery_stream.metrics[0].arn
  output_format = "json"

  # Include only essential namespaces
  dynamic "include_filter" {
    for_each = var.metric_stream_namespaces
    content {
      namespace = include_filter.value
    }
  }

  # Exclude high-volume, low-value metrics
  dynamic "exclude_filter" {
    for_each = var.excluded_metrics
    content {
      namespace    = exclude_filter.value.namespace
      metric_names = exclude_filter.value.metric_names
    }
  }

  tags = var.common_tags
}

# Kinesis Firehose for metric stream
resource "aws_kinesis_firehose_delivery_stream" "metrics" {
  count = var.enable_metric_stream ? 1 : 0

  name        = "${var.project_name}-${var.environment}-metrics"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = aws_iam_role.firehose[0].arn
    bucket_arn          = aws_s3_bucket.metrics[0].arn
    compression_format  = "GZIP"
    prefix              = "metrics/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "errors/"

    # Buffer settings for cost optimization
    buffering_interval = 900 # 15 minutes
    buffering_size     = 128 # 128 MB

    # Convert to Parquet for better compression and query performance
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
        database_name = aws_glue_catalog_database.metrics[0].name
        table_name    = aws_glue_catalog_table.metrics[0].name
      }
    }
  }

  tags = var.common_tags
}

# S3 bucket for metrics with lifecycle policy
resource "aws_s3_bucket" "metrics" {
  count = var.enable_metric_stream ? 1 : 0

  bucket = "${var.project_name}-${var.environment}-metrics-${data.aws_caller_identity.current.account_id}"

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-metrics"
      Type = "Metrics-Storage"
    }
  )
}

# Lifecycle policy for metrics bucket
resource "aws_s3_bucket_lifecycle_configuration" "metrics" {
  count = var.enable_metric_stream ? 1 : 0

  bucket = aws_s3_bucket.metrics[0].id

  rule {
    id     = "metrics-lifecycle"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = var.metrics_retention_days
    }
  }
}

# CloudWatch Logs Insights queries for cost analysis
resource "aws_cloudwatch_query_definition" "cost_analysis" {
  for_each = var.saved_queries

  name = each.key

  log_group_names = each.value.log_groups
  query_string    = each.value.query
}

# Dashboard with cost-optimized metrics
resource "aws_cloudwatch_dashboard" "cost_optimized" {
  dashboard_name = "${var.project_name}-${var.environment}-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          metrics = var.dashboard_metrics
          period  = 300
          stat    = "Average"
          region  = var.aws_region
          title   = "System Overview"
          annotations = {
            horizontal = var.dashboard_annotations
          }
        }
      },
      {
        type   = "log"
        width  = 12
        height = 6
        properties = {
          query  = var.dashboard_log_insights_query
          region = var.aws_region
          title  = "Recent Errors"
        }
      }
    ]
  })
}

# Log subscription filters with sampling
resource "aws_cloudwatch_log_subscription_filter" "sampled" {
  for_each = var.log_subscriptions

  name            = "${each.key}-subscription"
  log_group_name  = each.value.log_group_name
  filter_pattern  = each.value.filter_pattern
  destination_arn = each.value.destination_arn

  # Only available for Kinesis/Lambda destinations
  distribution = lookup(each.value, "sampling_enabled", false) ? "Random" : "ByLogStream"

  depends_on = [aws_cloudwatch_log_group.application_logs]
}

# Contributor Insights rules for cost analysis
resource "aws_cloudwatch_contributor_insights_rule" "api_usage" {
  count = var.enable_contributor_insights ? 1 : 0

  rule_name = "${var.project_name}-api-usage-by-user"
  rule_body = jsonencode({
    Version   = "1.0"
    LogFormat = "JSON"
    Contribution = {
      Filters = [
        {
          Match = "$.status_code"
          In    = [200, 201, 204]
        }
      ]
      Dimensions = ["$.user_id"]
    }
    AggregateOn = "Sum"
    Schema = {
      Name    = "CloudWatchLogRule"
      Version = "1.0"
    }
  })

  log_group_names = [aws_cloudwatch_log_group.application_logs["api-logs"].name]

  tags = var.common_tags
}

# IAM roles and policies
resource "aws_iam_role" "metric_stream" {
  count = var.enable_metric_stream ? 1 : 0

  name = "${var.project_name}-metric-stream-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "streams.metrics.cloudwatch.amazonaws.com"
      }
    }]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy" "metric_stream" {
  count = var.enable_metric_stream ? 1 : 0

  name = "metric-stream-policy"
  role = aws_iam_role.metric_stream[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "firehose:PutRecord",
        "firehose:PutRecordBatch"
      ]
      Resource = aws_kinesis_firehose_delivery_stream.metrics[0].arn
    }]
  })
}

resource "aws_iam_role" "firehose" {
  count = var.enable_metric_stream ? 1 : 0

  name = "${var.project_name}-firehose-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "firehose.amazonaws.com"
      }
    }]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy" "firehose" {
  count = var.enable_metric_stream ? 1 : 0

  name = "firehose-policy"
  role = aws_iam_role.firehose[0].id

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
          aws_s3_bucket.metrics[0].arn,
          "${aws_s3_bucket.metrics[0].arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "glue:GetTable",
          "glue:GetTableVersion",
          "glue:GetTableVersions"
        ]
        Resource = "*"
      }
    ]
  })
}

# Glue resources for Parquet conversion
resource "aws_glue_catalog_database" "metrics" {
  count = var.enable_metric_stream ? 1 : 0

  name = "${var.project_name}_metrics"
}

resource "aws_glue_catalog_table" "metrics" {
  count = var.enable_metric_stream ? 1 : 0

  name          = "cloudwatch_metrics"
  database_name = aws_glue_catalog_database.metrics[0].name

  table_type = "EXTERNAL_TABLE"

  parameters = {
    "projection.enabled"      = "true"
    "projection.year.type"    = "integer"
    "projection.year.range"   = "2023,2030"
    "projection.month.type"   = "integer"
    "projection.month.range"  = "1,12"
    "projection.month.digits" = "2"
    "projection.day.type"     = "integer"
    "projection.day.range"    = "1,31"
    "projection.day.digits"   = "2"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.metrics[0].bucket}/metrics/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      name                  = "ParquetSerde"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    columns {
      name = "timestamp"
      type = "bigint"
    }

    columns {
      name = "namespace"
      type = "string"
    }

    columns {
      name = "metric_name"
      type = "string"
    }

    columns {
      name = "dimensions"
      type = "map<string,string>"
    }

    columns {
      name = "value"
      type = "double"
    }

    columns {
      name = "unit"
      type = "string"
    }
  }
}

# Data source for account ID
data "aws_caller_identity" "current" {}

# Variables
variable "log_groups" {
  description = "Map of log groups to create"
  type = map(object({
    retention_days = optional(number)
    encrypted      = optional(bool)
    cost_center    = optional(string)
  }))
  default = {}
}

variable "default_retention_days" {
  description = "Default log retention days by environment"
  type        = map(number)
  default = {
    dev     = 7
    staging = 30
    prod    = 90
  }
}

variable "critical_log_metrics" {
  description = "Critical log metrics to create"
  type = map(object({
    log_group_name   = string
    filter_pattern   = string
    metric_name      = string
    metric_namespace = string
    metric_value     = string
    default_value    = optional(string)
    unit             = optional(string)
  }))
  default = {}
}

variable "composite_alarms" {
  description = "Composite alarms configuration"
  type = map(object({
    description = string
    alarm_rule  = string
  }))
  default = {}
}

variable "enable_metric_stream" {
  description = "Enable CloudWatch Metric Stream"
  type        = bool
  default     = false
}

variable "metric_stream_namespaces" {
  description = "Namespaces to include in metric stream"
  type        = list(string)
  default     = ["AWS/Lambda", "AWS/ApiGateway", "AWS/DynamoDB"]
}

variable "excluded_metrics" {
  description = "Metrics to exclude from stream"
  type = list(object({
    namespace    = string
    metric_names = list(string)
  }))
  default = []
}

variable "metrics_retention_days" {
  description = "Days to retain metrics in S3"
  type        = number
  default     = 365
}

variable "saved_queries" {
  description = "Saved CloudWatch Insights queries"
  type = map(object({
    log_groups = list(string)
    query      = string
  }))
  default = {}
}

variable "dashboard_metrics" {
  description = "Metrics for dashboard"
  type        = list(list(string))
  default     = []
}

variable "dashboard_annotations" {
  description = "Dashboard annotations"
  type = list(object({
    label = string
    value = number
  }))
  default = []
}

variable "dashboard_log_insights_query" {
  description = "Log Insights query for dashboard"
  type        = string
  default     = "fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 20"
}

variable "log_subscriptions" {
  description = "Log subscription filters"
  type = map(object({
    log_group_name   = string
    filter_pattern   = string
    destination_arn  = string
    sampling_enabled = optional(bool)
  }))
  default = {}
}

variable "enable_contributor_insights" {
  description = "Enable Contributor Insights"
  type        = bool
  default     = false
}

# Outputs
output "metric_stream_arn" {
  description = "CloudWatch Metric Stream ARN"
  value       = try(aws_cloudwatch_metric_stream.cost_optimized[0].arn, null)
}

output "metrics_bucket" {
  description = "S3 bucket for metrics"
  value       = try(aws_s3_bucket.metrics[0].id, null)
}

output "alarm_topic_arn" {
  description = "SNS topic for alarms"
  value       = aws_sns_topic.alarm_topic.arn
}

output "cost_optimization_summary" {
  description = "Summary of cost optimization measures"
  value = {
    log_groups_with_retention = length(aws_cloudwatch_log_group.application_logs)
    critical_metrics_only     = length(aws_cloudwatch_log_metric_filter.critical_metrics)
    composite_alarms          = length(aws_cloudwatch_composite_alarm.cost_optimized)
    metric_stream_enabled     = var.enable_metric_stream
  }
}