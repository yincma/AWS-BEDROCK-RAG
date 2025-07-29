# Data Compression Module for S3 Cost Optimization

# Lambda function for automatic compression
resource "aws_lambda_function" "s3_compressor" {
  count = length(var.compression_enabled_buckets) > 0 ? 1 : 0

  filename      = data.archive_file.compressor[0].output_path
  function_name = "${var.project_name}-${var.environment}-s3-compressor"
  role          = aws_iam_role.compressor[0].arn
  handler       = "index.handler"
  runtime       = var.lambda_runtime
  timeout       = 900  # 15 minutes
  memory_size   = 3008 # Max memory for better performance

  environment {
    variables = {
      COMPRESSION_TYPES   = jsonencode(local.all_compression_types)
      MIN_FILE_SIZE_BYTES = local.min_file_size
      SKIP_COMPRESSED     = "true"
      PARALLEL_PROCESSING = "true"
      MAX_WORKERS         = "10"
    }
  }

  # Enable Lambda Insights for performance monitoring
  layers = [
    "arn:aws:lambda:${data.aws_region.current.name}:580247275435:layer:LambdaInsightsExtension:14"
  ]

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-s3-compressor"
      Type = "Cost-Optimization"
    }
  )
}

# S3 event notifications for compression
resource "aws_s3_bucket_notification" "compression_trigger" {
  for_each = var.compression_enabled_buckets

  bucket = each.value.bucket_name

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_compressor[0].arn
    events              = ["s3:ObjectCreated:*"]

    # Only process specific file types
    filter_suffix = ".json"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_compressor[0].arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".log"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_compressor[0].arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".txt"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_compressor[0].arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".csv"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

# Lambda permission for S3 to invoke
resource "aws_lambda_permission" "allow_s3" {
  for_each = var.compression_enabled_buckets

  statement_id  = "AllowS3Invoke-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_compressor[0].function_name
  principal     = "s3.amazonaws.com"
  source_arn    = "arn:aws:s3:::${each.value.bucket_name}"
}

# Scheduled compression for existing files
resource "aws_cloudwatch_event_rule" "compression_schedule" {
  for_each = var.compression_enabled_buckets

  name                = "${var.project_name}-${var.environment}-compress-${each.key}"
  description         = "Scheduled compression for bucket ${each.value.bucket_name}"
  schedule_expression = each.value.schedule_expression

  tags = var.common_tags
}

resource "aws_cloudwatch_event_target" "compression_target" {
  for_each = var.compression_enabled_buckets

  rule      = aws_cloudwatch_event_rule.compression_schedule[each.key].name
  target_id = "CompressionLambda"
  arn       = aws_lambda_function.s3_compressor[0].arn

  input = jsonencode({
    bucket_name       = each.value.bucket_name
    compression_types = each.value.compression_types
    file_extensions   = each.value.file_extensions
    batch_mode        = true
  })
}

resource "aws_lambda_permission" "allow_eventbridge" {
  for_each = var.compression_enabled_buckets

  statement_id  = "AllowEventBridge-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_compressor[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.compression_schedule[each.key].arn
}

# Archive Lambda for moving old data
resource "aws_lambda_function" "s3_archiver" {
  count = length(var.archive_enabled_buckets) > 0 ? 1 : 0

  filename      = data.archive_file.archiver[0].output_path
  function_name = "${var.project_name}-${var.environment}-s3-archiver"
  role          = aws_iam_role.archiver[0].arn
  handler       = "index.handler"
  runtime       = var.lambda_runtime
  timeout       = 900
  memory_size   = 1024

  environment {
    variables = {
      ARCHIVE_PREFIX = "archive/"
      TAG_ARCHIVED   = "true"
    }
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-s3-archiver"
      Type = "Cost-Optimization"
    }
  )
}

# Archive schedule
resource "aws_cloudwatch_event_rule" "archive_schedule" {
  for_each = var.archive_enabled_buckets

  name                = "${var.project_name}-${var.environment}-archive-${each.key}"
  description         = "Archive old files in bucket ${each.value.bucket_name}"
  schedule_expression = "rate(1 day)"

  tags = var.common_tags
}

resource "aws_cloudwatch_event_target" "archive_target" {
  for_each = var.archive_enabled_buckets

  rule      = aws_cloudwatch_event_rule.archive_schedule[each.key].name
  target_id = "ArchiveLambda"
  arn       = aws_lambda_function.s3_archiver[0].arn

  input = jsonencode({
    bucket_name          = each.value.bucket_name
    archive_after_days   = each.value.archive_after_days
    archive_prefix       = each.value.archive_prefix
    delete_after_archive = each.value.delete_after_archive
  })
}

# Lambda code archives
data "archive_file" "compressor" {
  count = length(var.compression_enabled_buckets) > 0 ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/compressor.zip"

  source {
    content  = file("${path.module}/s3-compressor.py")
    filename = "index.py"
  }
}

data "archive_file" "archiver" {
  count = length(var.archive_enabled_buckets) > 0 ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/archiver.zip"

  source {
    content  = file("${path.module}/s3-archiver.py")
    filename = "index.py"
  }
}

# IAM roles and policies
resource "aws_iam_role" "compressor" {
  count = length(var.compression_enabled_buckets) > 0 ? 1 : 0

  name = "${var.project_name}-${var.environment}-compressor-role"

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

resource "aws_iam_role_policy" "compressor" {
  count = length(aws_iam_role.compressor) > 0 ? 1 : 0

  name = "compressor-policy"
  role = aws_iam_role.compressor[0].id

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
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObjectTagging",
          "s3:PutObjectTagging",
          "s3:ListBucket"
        ]
        Resource = flatten([
          for bucket in values(var.compression_enabled_buckets) : [
            "arn:aws:s3:::${bucket.bucket_name}",
            "arn:aws:s3:::${bucket.bucket_name}/*"
          ]
        ])
      },
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
      }
    ]
  })
}

# Similar IAM setup for archiver
resource "aws_iam_role" "archiver" {
  count = length(var.archive_enabled_buckets) > 0 ? 1 : 0

  name = "${var.project_name}-${var.environment}-archiver-role"

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

# CloudWatch metrics for compression monitoring
resource "aws_cloudwatch_log_metric_filter" "compression_metrics" {
  count = length(var.compression_enabled_buckets) > 0 ? 1 : 0

  name           = "${var.project_name}-compression-metrics"
  log_group_name = "/aws/lambda/${aws_lambda_function.s3_compressor[0].function_name}"
  pattern        = "[timestamp, request_id, level=INFO, msg=\"Compression complete\", original_size, compressed_size, ratio]"

  metric_transformation {
    name      = "CompressionRatio"
    namespace = "${var.project_name}/Storage"
    value     = "$ratio"
    unit      = "Percent"
  }
}

# Compression effectiveness dashboard
resource "aws_cloudwatch_dashboard" "compression_dashboard" {
  count = length(var.compression_enabled_buckets) > 0 ? 1 : 0

  dashboard_name = "${var.project_name}-${var.environment}-compression"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["${var.project_name}/Storage", "CompressionRatio", { stat = "Average" }],
            [".", "FilesCompressed", { stat = "Sum", yAxis = "right" }]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Compression Effectiveness"
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["${var.project_name}/Storage", "StorageSaved", { stat = "Sum" }]
          ]
          period = 86400
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Daily Storage Savings (GB)"
        }
      }
    ]
  })
}

# Data sources
data "aws_region" "current" {}

# Local variables
locals {
  # Aggregate all compression types
  all_compression_types = distinct(flatten([
    for bucket in values(var.compression_enabled_buckets) : bucket.compression_types
  ]))

  # Find minimum file size across all buckets
  min_file_size = min([
    for bucket in values(var.compression_enabled_buckets) : bucket.min_file_size_bytes
  ]...)

  # Estimate compression savings (70% compression ratio average)
  compression_ratio   = 0.7
  estimated_gb_saved  = 100 # Rough estimate
  storage_cost_per_gb = 0.023

  estimated_monthly_savings = local.estimated_gb_saved * local.compression_ratio * local.storage_cost_per_gb
}

# Outputs
output "compression_functions" {
  description = "Compression Lambda functions"
  value = {
    compressor = try(aws_lambda_function.s3_compressor[0].function_name, null)
    archiver   = try(aws_lambda_function.s3_archiver[0].function_name, null)
  }
}

output "compression_enabled_buckets" {
  description = "Buckets with compression enabled"
  value       = keys(var.compression_enabled_buckets)
}

output "archive_enabled_buckets" {
  description = "Buckets with archival enabled"
  value       = keys(var.archive_enabled_buckets)
}

output "compression_dashboard_url" {
  description = "CloudWatch dashboard for compression metrics"
  value       = try("https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.compression_dashboard[0].dashboard_name}", null)
}

output "estimated_monthly_savings" {
  description = "Estimated monthly savings from compression"
  value       = local.estimated_monthly_savings
}