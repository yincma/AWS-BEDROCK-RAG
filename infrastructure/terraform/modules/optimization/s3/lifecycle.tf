# S3 Lifecycle Configuration for Cost Optimization

# Lifecycle rules for different bucket types
resource "aws_s3_bucket_lifecycle_configuration" "optimized" {
  for_each = var.lifecycle_enabled_buckets

  bucket = each.key

  # Standard lifecycle rule for all objects
  rule {
    id     = "standard-lifecycle"
    status = "Enabled"

    # Transition to Infrequent Access
    transition {
      days          = lookup(each.value, "ia_transition_days", 30)
      storage_class = "STANDARD_IA"
    }

    # Transition to Glacier Flexible Retrieval
    transition {
      days          = lookup(each.value, "glacier_transition_days", 90)
      storage_class = "GLACIER"
    }

    # Transition to Glacier Deep Archive
    transition {
      days          = lookup(each.value, "deep_archive_days", 180)
      storage_class = "DEEP_ARCHIVE"
    }

    # Expiration
    expiration {
      days = lookup(each.value, "expiration_days", 365)
    }

    # Abort incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Rule for log files (aggressive lifecycle)
  rule {
    id     = "log-lifecycle"
    status = lookup(each.value, "has_logs", false) ? "Enabled" : "Disabled"

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
      days = lookup(each.value, "log_retention_days", 90)
    }
  }

  # Rule for temporary files
  rule {
    id     = "temp-lifecycle"
    status = "Enabled"

    filter {
      and {
        prefix = "temp/"
        tags = {
          temporary = "true"
        }
      }
    }

    expiration {
      days = 7
    }

    # Clean up expired object delete markers
    expiration {
      expired_object_delete_marker = true
    }
  }

  # Rule for old versions (versioning enabled buckets)
  rule {
    id     = "version-lifecycle"
    status = lookup(each.value, "versioning_enabled", false) ? "Enabled" : "Disabled"

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

  # Rule for multipart uploads cleanup
  rule {
    id     = "multipart-cleanup"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 3
    }
  }

  depends_on = [aws_s3_bucket_versioning.versioning]
}

# Intelligent Tiering configuration
resource "aws_s3_bucket_intelligent_tiering_configuration" "archive" {
  for_each = var.intelligent_tiering_buckets

  bucket = each.key
  name   = "${each.key}-intelligent-tiering"

  # Archive configurations
  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = lookup(each.value, "archive_days", 90)
  }

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = lookup(each.value, "deep_archive_days", 180)
  }

  # Filter configuration
  dynamic "filter" {
    for_each = lookup(each.value, "filter_prefix", null) != null ? [1] : []
    content {
      prefix = each.value.filter_prefix
    }
  }

  dynamic "filter" {
    for_each = lookup(each.value, "filter_tags", null) != null ? [1] : []
    content {
      tags = each.value.filter_tags
    }
  }

  status = "Enabled"
}

# S3 Inventory configuration for cost analysis
resource "aws_s3_bucket_inventory" "cost_analysis" {
  for_each = var.inventory_enabled_buckets

  bucket = each.key
  name   = "${each.key}-inventory"

  included_object_versions = "Current"

  schedule {
    frequency = lookup(each.value, "frequency", "Weekly")
  }

  destination {
    bucket {
      format     = "CSV"
      bucket_arn = aws_s3_bucket.inventory_destination.arn
      prefix     = "inventory/${each.key}/"

      encryption {
        sse_s3 {
          # Server-side encryption with S3-managed keys
        }
      }
    }
  }

  # Fields to include in inventory
  optional_fields = [
    "Size",
    "LastModifiedDate",
    "StorageClass",
    "ETag",
    "IsMultipartUploaded",
    "ReplicationStatus",
    "EncryptionStatus",
    "ObjectLockRetainUntilDate",
    "ObjectLockMode",
    "ObjectLockLegalHoldStatus",
    "IntelligentTieringAccessTier",
    "BucketKeyStatus"
  ]

  filter {
    prefix = lookup(each.value, "inventory_prefix", "")
  }
}

# Inventory destination bucket
resource "aws_s3_bucket" "inventory_destination" {
  bucket = "${var.bucket_prefix}-inventory-${var.environment}"

  tags = merge(
    var.common_tags,
    {
      Name = "${var.bucket_prefix}-inventory"
      Type = "Inventory-Storage"
    }
  )
}

# Inventory bucket policy
resource "aws_s3_bucket_policy" "inventory_destination" {
  bucket = aws_s3_bucket.inventory_destination.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowInventoryReports"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = [
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.inventory_destination.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# S3 Storage Lens configuration
resource "aws_s3control_storage_lens_configuration" "cost_optimization" {
  config_id = "${var.bucket_prefix}-cost-optimization"

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

    # Data export configuration
    data_export {
      s3_bucket_destination {
        format                = "CSV"
        output_schema_version = "V_1"
        bucket_arn            = aws_s3_bucket.inventory_destination.arn
        prefix                = "storage-lens/"

        encryption {
          sse_s3 {}
        }
      }
    }

    # Exclude specific buckets if needed
    dynamic "exclude" {
      for_each = var.storage_lens_exclude_buckets
      content {
        buckets = [exclude.value]
      }
    }
  }
}

# Request metrics for frequently accessed objects
resource "aws_s3_bucket_request_payment_configuration" "requester_pays" {
  for_each = var.requester_pays_buckets

  bucket = each.key
  payer  = "Requester"
}

# Enable S3 Transfer Acceleration for better performance
resource "aws_s3_bucket_accelerate_configuration" "acceleration" {
  for_each = var.transfer_acceleration_buckets

  bucket = each.key
  status = "Enabled"
}

# Variables
variable "lifecycle_enabled_buckets" {
  description = "Map of buckets with lifecycle configuration"
  type = map(object({
    ia_transition_days      = optional(number)
    glacier_transition_days = optional(number)
    deep_archive_days       = optional(number)
    expiration_days         = optional(number)
    has_logs                = optional(bool)
    log_retention_days      = optional(number)
    versioning_enabled      = optional(bool)
  }))
  default = {}
}

variable "intelligent_tiering_buckets" {
  description = "Buckets to enable intelligent tiering"
  type = map(object({
    archive_days      = optional(number)
    deep_archive_days = optional(number)
    filter_prefix     = optional(string)
    filter_tags       = optional(map(string))
  }))
  default = {}
}

variable "inventory_enabled_buckets" {
  description = "Buckets to enable inventory reports"
  type = map(object({
    frequency        = optional(string)
    inventory_prefix = optional(string)
  }))
  default = {}
}

variable "bucket_prefix" {
  description = "Prefix for bucket names"
  type        = string
}

variable "storage_lens_exclude_buckets" {
  description = "Buckets to exclude from Storage Lens"
  type        = list(string)
  default     = []
}

variable "requester_pays_buckets" {
  description = "Buckets to enable requester pays"
  type        = set(string)
  default     = []
}

variable "transfer_acceleration_buckets" {
  description = "Buckets to enable transfer acceleration"
  type        = set(string)
  default     = []
}

# Outputs
output "lifecycle_rules_count" {
  description = "Number of lifecycle rules configured"
  value       = length(aws_s3_bucket_lifecycle_configuration.optimized)
}

output "intelligent_tiering_count" {
  description = "Number of intelligent tiering configurations"
  value       = length(aws_s3_bucket_intelligent_tiering_configuration.archive)
}

output "inventory_configurations" {
  description = "Inventory configuration details"
  value = {
    for k, v in aws_s3_bucket_inventory.cost_analysis : k => {
      frequency   = v.schedule[0].frequency
      destination = v.destination[0].bucket[0].bucket_arn
    }
  }
}

output "storage_lens_dashboard_url" {
  description = "URL to Storage Lens dashboard"
  value       = "https://s3.console.aws.amazon.com/s3/lens/${aws_s3control_storage_lens_configuration.cost_optimization.config_id}"
}