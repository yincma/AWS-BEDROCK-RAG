# S3 Lifecycle Management for Cost Optimization

# Data source for existing buckets
data "aws_s3_bucket" "existing" {
  for_each = var.buckets
  bucket   = each.value.bucket_name
}

# Lifecycle rules for each bucket
resource "aws_s3_bucket_lifecycle_configuration" "optimized" {
  for_each = { for k, v in var.buckets : k => v if v.enable_lifecycle }

  bucket = data.aws_s3_bucket.existing[each.key].id

  # Rule 1: Standard object lifecycle
  rule {
    id     = "${each.key}-standard-lifecycle"
    status = "Enabled"

    # Filter for non-log files
    filter {
      and {
        prefix = ""
        tags = {
          "lifecycle" = "standard"
        }
      }
    }

    # Transition to Infrequent Access
    transition {
      days          = each.value.lifecycle_rules.ia_transition_days
      storage_class = "STANDARD_IA"
    }

    # Transition to Glacier Flexible Retrieval
    transition {
      days          = each.value.lifecycle_rules.glacier_transition_days
      storage_class = "GLACIER"
    }

    # Transition to Glacier Deep Archive
    transition {
      days          = each.value.lifecycle_rules.deep_archive_days
      storage_class = "DEEP_ARCHIVE"
    }

    # Expiration (optional)
    dynamic "expiration" {
      for_each = each.value.lifecycle_rules.expiration_days != null ? [1] : []
      content {
        days = each.value.lifecycle_rules.expiration_days
      }
    }

    # Abort incomplete multipart uploads
    dynamic "abort_incomplete_multipart_upload" {
      for_each = each.value.lifecycle_rules.enable_multipart_cleanup ? [1] : []
      content {
        days_after_initiation = 7
      }
    }
  }

  # Rule 2: Aggressive lifecycle for logs
  rule {
    id     = "${each.key}-log-lifecycle"
    status = "Enabled"

    filter {
      prefix = "logs/"
    }

    transition {
      days          = 7
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    expiration {
      days = each.value.lifecycle_rules.log_retention_days
    }

    # Clean up expired delete markers
    expiration {
      expired_object_delete_marker = true
    }
  }

  # Rule 3: Temporary files cleanup
  rule {
    id     = "${each.key}-temp-cleanup"
    status = "Enabled"

    filter {
      and {
        prefix = "temp/"
        tags = {
          "temporary" = "true"
        }
      }
    }

    expiration {
      days = 3
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  # Rule 4: Version cleanup (if versioning is enabled)
  dynamic "rule" {
    for_each = each.value.lifecycle_rules.enable_version_cleanup ? [1] : []
    content {
      id     = "${each.key}-version-cleanup"
      status = "Enabled"

      # Apply to all objects
      filter {}

      noncurrent_version_transition {
        noncurrent_days = 30
        storage_class   = "STANDARD_IA"
      }

      noncurrent_version_transition {
        noncurrent_days = 60
        storage_class   = "GLACIER"
      }

      noncurrent_version_expiration {
        noncurrent_days = 90
      }
    }
  }

  # Rule 5: Archive old backups
  rule {
    id     = "${each.key}-backup-archive"
    status = "Enabled"

    filter {
      prefix = "backups/"
    }

    transition {
      days          = 1
      storage_class = "GLACIER"
    }

    transition {
      days          = 30
      storage_class = "DEEP_ARCHIVE"
    }
  }
}

# Intelligent Tiering Configuration
resource "aws_s3_bucket_intelligent_tiering_configuration" "auto_tiering" {
  for_each = { for k, v in var.buckets : k => v if v.enable_intelligent_tiering }

  bucket = data.aws_s3_bucket.existing[each.key].id
  name   = "${each.key}-intelligent-tiering"

  # Archive access tier configuration
  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = each.value.intelligent_tiering_config.archive_days
  }

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = each.value.intelligent_tiering_config.deep_archive_days
  }

  # Optional filter
  dynamic "filter" {
    for_each = each.value.intelligent_tiering_config.filter_prefix != null ? [1] : []
    content {
      prefix = each.value.intelligent_tiering_config.filter_prefix

      dynamic "tag" {
        for_each = each.value.intelligent_tiering_config.filter_tags != null ? each.value.intelligent_tiering_config.filter_tags : {}
        content {
          key   = tag.key
          value = tag.value
        }
      }
    }
  }

  status = "Enabled"
}

# S3 Inventory for cost analysis
resource "aws_s3_bucket_inventory" "cost_analysis" {
  for_each = { for k, v in var.buckets : k => v if v.enable_inventory && var.enable_inventory }

  bucket = data.aws_s3_bucket.existing[each.key].id
  name   = "${each.key}-cost-inventory"

  included_object_versions = "Current"

  schedule {
    frequency = "Weekly"
  }

  destination {
    bucket {
      format     = "Parquet" # More efficient than CSV
      bucket_arn = aws_s3_bucket.inventory_destination[0].arn
      prefix     = "inventory/${each.key}/"

      encryption {
        sse_s3 {
          # S3-managed encryption
        }
      }
    }
  }

  # Essential fields only to reduce costs
  optional_fields = [
    "Size",
    "LastModifiedDate",
    "StorageClass",
    "IntelligentTieringAccessTier"
  ]

  filter {
    prefix = ""
  }
}

# Central inventory bucket (only one needed)
resource "aws_s3_bucket" "inventory_destination" {
  count  = var.enable_inventory ? 1 : 0
  bucket = "${var.project_name}-${var.environment}-s3-inventory-${data.aws_caller_identity.current.account_id}"

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.project_name}-inventory"
      Type        = "Cost-Analysis"
      Environment = var.environment
    }
  )
}

# Inventory bucket lifecycle
resource "aws_s3_bucket_lifecycle_configuration" "inventory_lifecycle" {
  count  = var.enable_inventory ? 1 : 0
  bucket = aws_s3_bucket.inventory_destination[0].id

  rule {
    id     = "inventory-cleanup"
    status = "Enabled"

    filter {}

    # Keep inventory data for 90 days
    expiration {
      days = 90
    }
  }
}

# Inventory bucket policy
resource "aws_s3_bucket_policy" "inventory_policy" {
  count  = var.enable_inventory ? 1 : 0
  bucket = aws_s3_bucket.inventory_destination[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowInventoryReports"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.inventory_destination[0].arn}/*"
        Condition = {
          ArnLike = {
            "aws:SourceArn" = [
              for k, v in var.buckets : data.aws_s3_bucket.existing[k].arn if v.enable_inventory
            ]
          }
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# S3 Storage Lens Configuration
resource "aws_s3control_storage_lens_configuration" "optimization_insights" {
  count     = var.enable_storage_lens ? 1 : 0
  config_id = "${var.project_name}-${var.environment}-storage-insights"

  storage_lens_configuration {
    enabled = true

    account_level {
      activity_metrics {
        enabled = true
      }

      bucket_level {
        activity_metrics {
          enabled = true
        }

        prefix_level {
          storage_metrics {
            enabled = true

            selection_criteria {
              delimiter                    = "/"
              max_depth                    = 3
              min_storage_bytes_percentage = 1.0
            }
          }
        }
      }
    }

    # Export configuration for detailed analysis
    data_export {
      s3_bucket_destination {
        format                = "Parquet"
        output_schema_version = "V_1"
        bucket_arn            = aws_s3_bucket.inventory_destination[0].arn
        prefix                = "storage-lens/"

        encryption {
          sse_s3 {}
        }
      }
    }

    # Include only optimized buckets
    include {
      buckets = [for k, v in var.buckets : data.aws_s3_bucket.existing[k].arn]
    }
  }
}

# Data source for current account
data "aws_caller_identity" "current" {}

# Calculate estimated savings
locals {
  # Estimate 30% savings from lifecycle policies
  lifecycle_savings = sum([
    for k, v in var.buckets :
    v.enable_lifecycle ? 0.3 : 0
  ]) * 100 # Rough estimate: $100 per bucket per month

  # Estimate 20% savings from intelligent tiering
  tiering_savings = sum([
    for k, v in var.buckets :
    v.enable_intelligent_tiering ? 0.2 : 0
  ]) * 50 # Rough estimate: $50 per bucket per month
}

# Outputs
output "lifecycle_configurations" {
  description = "Lifecycle configurations applied"
  value = {
    for k, v in aws_s3_bucket_lifecycle_configuration.optimized :
    k => {
      bucket = v.bucket
      rules  = length(v.rule)
    }
  }
}

output "intelligent_tiering_count" {
  description = "Number of buckets with intelligent tiering"
  value       = length(aws_s3_bucket_intelligent_tiering_configuration.auto_tiering)
}

output "lifecycle_rules_count" {
  description = "Total number of lifecycle rules"
  value = sum([
    for k, v in aws_s3_bucket_lifecycle_configuration.optimized :
    length(v.rule)
  ])
}

output "inventory_bucket" {
  description = "S3 inventory destination bucket"
  value       = try(aws_s3_bucket.inventory_destination[0].id, null)
}

output "storage_lens_dashboard_url" {
  description = "URL to Storage Lens dashboard"
  value       = var.enable_storage_lens ? "https://s3.console.aws.amazon.com/s3/lens/${var.project_name}-${var.environment}-storage-insights" : null
}

output "estimated_monthly_savings" {
  description = "Estimated monthly savings from S3 optimizations"
  value       = local.lifecycle_savings + local.tiering_savings
}