# S3 Storage Optimization Module
# 实现生命周期策略、智能分层、日志优化和数据压缩

# S3 生命周期策略配置
resource "aws_s3_bucket_lifecycle_configuration" "optimized_storage" {
  for_each = var.s3_buckets

  bucket = each.value.bucket_name

  # 规则1: 文档索引生命周期
  rule {
    id     = "document-index-lifecycle"
    status = "Enabled"

    filter {
      prefix = "document-index/"
    }

    # 30天后转移到IA存储类
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # 90天后转移到Glacier
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # 365天后转移到Deep Archive
    transition {
      days          = 365
      storage_class = "DEEP_ARCHIVE"
    }

    # 7年后删除（符合合规要求）
    expiration {
      days = 2555 # 7 years
    }
  }

  # 规则2: 日志文件生命周期
  rule {
    id     = "log-files-lifecycle"
    status = "Enabled"

    filter {
      prefix = "logs/"
    }

    # 7天后转移到IA
    transition {
      days          = 7
      storage_class = "STANDARD_IA"
    }

    # 30天后转移到Glacier
    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    # 90天后删除日志
    expiration {
      days = 90
    }
  }

  # 规则3: 临时文件清理
  rule {
    id     = "temp-files-cleanup"
    status = "Enabled"

    filter {
      prefix = "temp/"
    }

    # 1天后删除临时文件
    expiration {
      days = 1
    }

    # 清理未完成的分段上传
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  # 规则4: 备份文件优化
  rule {
    id     = "backup-optimization"
    status = "Enabled"

    filter {
      prefix = "backups/"
    }

    # 立即转移到IA
    transition {
      days          = 0
      storage_class = "STANDARD_IA"
    }

    # 30天后转移到Glacier
    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    # 启用非当前版本过期
    noncurrent_version_transition {
      noncurrent_days = 7
      storage_class   = "GLACIER"
    }

    # 30天后删除非当前版本
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# S3 智能分层配置
resource "aws_s3_bucket_intelligent_tiering_configuration" "auto_tiering" {
  for_each = var.intelligent_tiering_buckets

  bucket = each.value.bucket_name
  name   = "${each.key}-intelligent-tiering"

  # 启用深度存档访问层
  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = 180
  }

  # 启用存档访问层
  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 90
  }

  # 过滤条件
  filter {
    prefix = each.value.prefix

    dynamic "tag" {
      for_each = each.value.tags
      content {
        key   = tag.value.key
        value = tag.value.value
      }
    }
  }

  status = "Enabled"
}

# CloudWatch日志组保留期优化
resource "aws_cloudwatch_log_group" "optimized_logs" {
  for_each = var.log_groups

  name              = each.value.name
  retention_in_days = each.value.retention_days
  kms_key_id        = var.kms_key_id

  tags = merge(
    var.tags,
    {
      RetentionOptimized = "true"
      RetentionDays      = each.value.retention_days
    }
  )
}

# 日志订阅过滤器（用于压缩和归档）
resource "aws_cloudwatch_log_subscription_filter" "log_compression" {
  for_each = var.log_compression_config

  name            = "${each.key}-compression-filter"
  log_group_name  = each.value.log_group_name
  filter_pattern  = each.value.filter_pattern
  destination_arn = aws_lambda_function.log_compressor.arn

  depends_on = [aws_lambda_permission.allow_cloudwatch]
}

# 日志压缩Lambda函数
resource "aws_lambda_function" "log_compressor" {
  function_name = "cloudwatch-log-compressor"
  description   = "Compress and archive CloudWatch logs to S3"
  role          = aws_iam_role.log_compressor.arn
  handler       = "index.handler"
  runtime       = "python3.9"
  timeout       = 300
  memory_size   = 1024

  environment {
    variables = {
      ARCHIVE_BUCKET    = var.log_archive_bucket
      COMPRESSION_LEVEL = var.compression_level
      ENCRYPTION_KEY_ID = var.kms_key_id
    }
  }

  filename         = "${path.module}/lambda/log-compressor.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda/log-compressor.zip")

  reserved_concurrent_executions = 10

  tags = var.tags
}

# Lambda IAM角色
resource "aws_iam_role" "log_compressor" {
  name = "log-compressor-lambda-role"

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

# Lambda IAM策略
resource "aws_iam_role_policy" "log_compressor" {
  name = "log-compressor-policy"
  role = aws_iam_role.log_compressor.id

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
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${var.log_archive_bucket}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = var.kms_key_id != "" ? var.kms_key_id : "*"
      }
    ]
  })
}

# CloudWatch权限
resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatchLogs"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.log_compressor.function_name
  principal     = "logs.amazonaws.com"
}

# S3存储类分析配置
resource "aws_s3_bucket_analytics_configuration" "storage_class_analysis" {
  for_each = var.s3_buckets

  bucket = each.value.bucket_name
  name   = "${each.key}-storage-analysis"

  filter {
    prefix = each.value.analysis_prefix
  }

  storage_class_analysis {
    data_export {
      destination {
        s3_bucket_destination {
          bucket_arn = "arn:aws:s3:::${var.analytics_bucket}"
          prefix     = "storage-class-analysis/${each.key}"
        }
      }
      output_schema_version = "V_1"
    }
  }
}

# 成本优化仪表板
resource "aws_cloudwatch_dashboard" "storage_cost_optimization" {
  dashboard_name = "storage-cost-optimization"

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
            ["AWS/S3", "BucketSizeBytes", { stat = "Average" }],
            ["...", { stat = "Sum" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "S3 Bucket Size Trends"
          period  = 86400 # Daily
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
            ["AWS/S3", "NumberOfObjects", { stat = "Average" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "S3 Object Count"
          period  = 86400
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
            [{ expression = "SEARCH(' StorageType=\"StandardStorage\" ', 'Average', 86400)" }],
            [{ expression = "SEARCH(' StorageType=\"StandardIAStorage\" ', 'Average', 86400)" }],
            [{ expression = "SEARCH(' StorageType=\"GlacierStorage\" ', 'Average', 86400)" }]
          ]
          view    = "timeSeries"
          stacked = true
          region  = data.aws_region.current.name
          title   = "Storage Class Distribution"
          period  = 86400
          yAxis = {
            left = {
              label = "Bytes"
            }
          }
        }
      }
    ]
  })
}

# 输出优化配置
output "storage_optimization_config" {
  value = {
    lifecycle_rules_count        = length(var.s3_buckets) * 4
    intelligent_tiering_enabled  = length(var.intelligent_tiering_buckets)
    log_retention_optimized      = length(var.log_groups)
    compression_enabled          = length(var.log_compression_config) > 0
    estimated_savings_percentage = 30 # Target savings
  }
  description = "Storage optimization configuration summary"
}

# 数据源
data "aws_region" "current" {}

# 变量定义
variable "s3_buckets" {
  description = "S3 buckets to apply lifecycle policies"
  type = map(object({
    bucket_name     = string
    analysis_prefix = string
  }))
  default = {}
}

variable "intelligent_tiering_buckets" {
  description = "Buckets to enable intelligent tiering"
  type = map(object({
    bucket_name = string
    prefix      = string
    tags = list(object({
      key   = string
      value = string
    }))
  }))
  default = {}
}

variable "log_groups" {
  description = "CloudWatch log groups with optimized retention"
  type = map(object({
    name           = string
    retention_days = number
  }))
  default = {}
}

variable "log_compression_config" {
  description = "Log compression configuration"
  type = map(object({
    log_group_name = string
    filter_pattern = string
  }))
  default = {}
}

variable "log_archive_bucket" {
  description = "S3 bucket for compressed log archives"
  type        = string
}

variable "analytics_bucket" {
  description = "S3 bucket for storage analytics"
  type        = string
}

variable "compression_level" {
  description = "Compression level (1-9)"
  type        = number
  default     = 6
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