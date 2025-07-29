# Data Compression Module
# 实现各种文件类型的数据压缩以降低存储成本

# 数据压缩Lambda函数
resource "aws_lambda_function" "data_compressor" {
  function_name = "${var.environment}-data-compressor"
  description   = "Compress various file types to reduce storage costs"
  role          = aws_iam_role.data_compressor.arn
  handler       = "index.handler"
  runtime       = "python3.9"
  timeout       = 900 # 15 minutes for large files
  memory_size   = 3008

  environment {
    variables = {
      COMPRESSION_SETTINGS = jsonencode(var.compression_settings)
      TARGET_BUCKET        = var.target_bucket
      ENABLE_ENCRYPTION    = var.enable_encryption
      KMS_KEY_ID           = var.kms_key_id
    }
  }

  filename         = data.archive_file.compressor_lambda.output_path
  source_code_hash = data.archive_file.compressor_lambda.output_base64sha256

  reserved_concurrent_executions = var.reserved_concurrency

  layers = [
    aws_lambda_layer_version.compression_libs.arn
  ]

  tags = var.tags
}

# Lambda层 - 压缩库
resource "aws_lambda_layer_version" "compression_libs" {
  filename   = "${path.module}/layers/compression-libs.zip"
  layer_name = "compression-libraries"

  compatible_runtimes = ["python3.9", "python3.10"]

  description = "Compression libraries: zstandard, brotli, lz4"
}

# IAM角色
resource "aws_iam_role" "data_compressor" {
  name = "${var.environment}-data-compressor-role"

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

# IAM策略
resource "aws_iam_role_policy" "data_compressor" {
  name = "data-compressor-policy"
  role = aws_iam_role.data_compressor.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectTagging"
        ]
        Resource = var.source_bucket_arns
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectTagging",
          "s3:PutObjectAcl"
        ]
        Resource = "${var.target_bucket}/*"
      },
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
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = var.kms_key_id != "" ? var.kms_key_id : "*"
      }
    ]
  })
}

# S3事件触发器 - 自动压缩新文件
resource "aws_s3_bucket_notification" "compression_trigger" {
  for_each = var.compression_triggers

  bucket = each.value.bucket_name

  lambda_function {
    lambda_function_arn = aws_lambda_function.data_compressor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = each.value.prefix
    filter_suffix       = each.value.suffix
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

# Lambda权限 - 允许S3触发
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.data_compressor.function_name
  principal     = "s3.amazonaws.com"
}

# 压缩任务队列 - 处理大批量文件
resource "aws_sqs_queue" "compression_queue" {
  name                       = "${var.environment}-compression-queue"
  visibility_timeout_seconds = 960   # 16 minutes
  message_retention_seconds  = 86400 # 1 day

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.compression_dlq.arn
    maxReceiveCount     = 3
  })

  tags = var.tags
}

# 死信队列
resource "aws_sqs_queue" "compression_dlq" {
  name = "${var.environment}-compression-dlq"

  tags = var.tags
}

# 批量压缩Step Functions状态机
resource "aws_sfn_state_machine" "batch_compression" {
  name     = "${var.environment}-batch-compression"
  role_arn = aws_iam_role.step_functions.arn

  definition = jsonencode({
    Comment = "Batch compression workflow for large datasets"
    StartAt = "ListObjects"
    States = {
      ListObjects = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:s3:listObjectsV2"
        Parameters = {
          Bucket  = var.source_bucket
          Prefix  = "${var.batch_prefix}"
          MaxKeys = 1000
        }
        Next = "ProcessObjects"
      }
      ProcessObjects = {
        Type           = "Map"
        ItemsPath      = "$.Contents"
        MaxConcurrency = 10
        Iterator = {
          StartAt = "CheckCompression"
          States = {
            CheckCompression = {
              Type     = "Task"
              Resource = aws_lambda_function.compression_checker.arn
              Parameters = {
                "bucket.$" = "$.bucket"
                "key.$"    = "$.Key"
                "size.$"   = "$.Size"
              }
              Next = "CompressIfNeeded"
            }
            CompressIfNeeded = {
              Type = "Choice"
              Choices = [
                {
                  Variable      = "$.shouldCompress"
                  BooleanEquals = true
                  Next          = "CompressFile"
                }
              ]
              Default = "Skip"
            }
            CompressFile = {
              Type     = "Task"
              Resource = aws_lambda_function.data_compressor.arn
              Parameters = {
                "bucket.$"          = "$.bucket"
                "key.$"             = "$.key"
                "compressionType.$" = "$.recommendedCompression"
              }
              End = true
            }
            Skip = {
              Type = "Pass"
              End  = true
            }
          }
        }
        End = true
      }
    }
  })

  tags = var.tags
}

# 压缩检查Lambda
resource "aws_lambda_function" "compression_checker" {
  function_name = "${var.environment}-compression-checker"
  description   = "Check if file should be compressed"
  role          = aws_iam_role.data_compressor.arn
  handler       = "checker.handler"
  runtime       = "python3.9"
  timeout       = 60
  memory_size   = 512

  environment {
    variables = {
      MIN_FILE_SIZE      = var.min_file_size_for_compression
      COMPRESSIBLE_TYPES = jsonencode(var.compressible_file_types)
    }
  }

  filename         = data.archive_file.checker_lambda.output_path
  source_code_hash = data.archive_file.checker_lambda.output_base64sha256

  tags = var.tags
}

# Step Functions IAM角色
resource "aws_iam_role" "step_functions" {
  name = "${var.environment}-compression-sfn-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "step_functions" {
  name = "compression-sfn-policy"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.data_compressor.arn,
          aws_lambda_function.compression_checker.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject"
        ]
        Resource = "*"
      }
    ]
  })
}

# CloudWatch监控仪表板
resource "aws_cloudwatch_dashboard" "compression_dashboard" {
  dashboard_name = "${var.environment}-compression-dashboard"

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
            ["AWS/Lambda", "Invocations", { "FunctionName" : aws_lambda_function.data_compressor.function_name }],
            [".", "Errors", ".", ".", { stat = "Sum" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Compression Function Activity"
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
            ["CompressionMetrics", "BytesProcessed", { stat = "Sum" }],
            [".", "BytesSaved", ".", { stat = "Sum" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Compression Savings"
          period  = 300
          yAxis = {
            left = {
              label = "Bytes"
            }
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
            ["CompressionMetrics", "CompressionRatio", { stat = "Average" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Average Compression Ratio"
          period  = 3600
          annotations = {
            horizontal = [
              {
                label = "Target Ratio"
                value = 0.5
              }
            ]
          }
        }
      }
    ]
  })
}

# Lambda代码打包
data "archive_file" "compressor_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/compressor.py"
  output_path = "${path.module}/lambda/compressor.zip"
}

data "archive_file" "checker_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/checker.py"
  output_path = "${path.module}/lambda/checker.zip"
}

# 数据源
data "aws_region" "current" {}

# 输出
output "compression_config" {
  value = {
    compressor_function_name = aws_lambda_function.data_compressor.function_name
    compression_queue_url    = aws_sqs_queue.compression_queue.url
    batch_compression_arn    = aws_sfn_state_machine.batch_compression.arn
    compression_triggers     = keys(var.compression_triggers)
  }
  description = "Data compression configuration"
}

# 变量定义
variable "environment" {
  description = "Environment name"
  type        = string
}

variable "compression_settings" {
  description = "Compression settings by file type"
  type = map(object({
    algorithm   = string
    level       = number
    min_size_mb = number
    extensions  = list(string)
  }))
  default = {
    text = {
      algorithm   = "gzip"
      level       = 9
      min_size_mb = 1
      extensions  = [".txt", ".log", ".csv", ".json", ".xml"]
    }
    documents = {
      algorithm   = "zstd"
      level       = 3
      min_size_mb = 5
      extensions  = [".pdf", ".doc", ".docx"]
    }
    images = {
      algorithm   = "webp"
      level       = 80
      min_size_mb = 1
      extensions  = [".jpg", ".jpeg", ".png"]
    }
    data = {
      algorithm   = "lz4"
      level       = 1
      min_size_mb = 10
      extensions  = [".parquet", ".avro", ".orc"]
    }
  }
}

variable "target_bucket" {
  description = "Target S3 bucket for compressed files"
  type        = string
}

variable "source_bucket" {
  description = "Source S3 bucket"
  type        = string
}

variable "source_bucket_arns" {
  description = "List of source bucket ARNs"
  type        = list(string)
}

variable "batch_prefix" {
  description = "Prefix for batch compression"
  type        = string
  default     = ""
}

variable "compression_triggers" {
  description = "S3 event triggers for automatic compression"
  type = map(object({
    bucket_name = string
    prefix      = string
    suffix      = string
  }))
  default = {}
}

variable "enable_encryption" {
  description = "Enable encryption for compressed files"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for encryption"
  type        = string
  default     = ""
}

variable "reserved_concurrency" {
  description = "Reserved concurrent executions for Lambda"
  type        = number
  default     = 10
}

variable "min_file_size_for_compression" {
  description = "Minimum file size in bytes for compression"
  type        = number
  default     = 1048576 # 1 MB
}

variable "compressible_file_types" {
  description = "List of file extensions that can be compressed"
  type        = list(string)
  default = [
    ".txt", ".log", ".csv", ".json", ".xml",
    ".html", ".css", ".js", ".sql",
    ".pdf", ".doc", ".docx", ".xls", ".xlsx"
  ]
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}