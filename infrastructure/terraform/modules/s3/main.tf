# S3 Module - S3 桶创建和配置

# 创建 S3 桶
resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name

  tags = merge(
    var.tags,
    {
      Name = var.bucket_name
      Type = var.bucket_type
    }
  )
}

# 桶版本控制
resource "aws_s3_bucket_versioning" "this" {
  count = var.enable_versioning ? 1 : 0

  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

# 服务器端加密
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.encryption_algorithm
      kms_master_key_id = var.encryption_algorithm == "aws:kms" ? var.kms_key_id : null
    }
    bucket_key_enabled = var.encryption_algorithm == "aws:kms" ? var.bucket_key_enabled : null
  }
}

# 公共访问阻止
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = var.block_public_access
  block_public_policy     = var.block_public_access
  ignore_public_acls      = var.block_public_access
  restrict_public_buckets = var.block_public_access
}

# 生命周期规则
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count = length(var.lifecycle_rules) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  dynamic "rule" {
    for_each = var.lifecycle_rules

    content {
      id     = rule.value.id
      status = rule.value.enabled ? "Enabled" : "Disabled"

      # 过期规则
      dynamic "expiration" {
        for_each = lookup(rule.value, "expiration_days", null) != null ? [1] : []

        content {
          days = rule.value.expiration_days
        }
      }

      # 非当前版本过期
      dynamic "noncurrent_version_expiration" {
        for_each = lookup(rule.value, "noncurrent_version_expiration_days", null) != null ? [1] : []

        content {
          noncurrent_days = rule.value.noncurrent_version_expiration_days
        }
      }

      # 转换规则
      dynamic "transition" {
        for_each = lookup(rule.value, "transitions", [])

        content {
          days          = transition.value.days
          storage_class = transition.value.storage_class
        }
      }

      # 非当前版本转换
      dynamic "noncurrent_version_transition" {
        for_each = lookup(rule.value, "noncurrent_version_transitions", [])

        content {
          noncurrent_days = noncurrent_version_transition.value.days
          storage_class   = noncurrent_version_transition.value.storage_class
        }
      }

      # 过滤条件
      dynamic "filter" {
        for_each = lookup(rule.value, "prefix", null) != null || lookup(rule.value, "tags", null) != null ? [1] : []

        content {
          prefix = lookup(rule.value, "prefix", null)

          dynamic "tag" {
            for_each = lookup(rule.value, "tags", {})

            content {
              key   = tag.key
              value = tag.value
            }
          }
        }
      }
    }
  }
}

# 跨区域复制配置
resource "aws_s3_bucket_replication_configuration" "this" {
  count = var.enable_replication ? 1 : 0

  role   = var.replication_role_arn
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "replicate-all"
    status = "Enabled"

    filter {}

    destination {
      bucket        = var.replication_destination_bucket_arn
      storage_class = var.replication_storage_class

      # 加密配置
      dynamic "encryption_configuration" {
        for_each = var.replication_kms_key_id != null ? [1] : []

        content {
          replica_kms_key_id = var.replication_kms_key_id
        }
      }
    }

    delete_marker_replication {
      status = var.replicate_delete_markers ? "Enabled" : "Disabled"
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

# CORS 配置
resource "aws_s3_bucket_cors_configuration" "this" {
  count = length(var.cors_rules) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  dynamic "cors_rule" {
    for_each = var.cors_rules

    content {
      id              = lookup(cors_rule.value, "id", null)
      allowed_headers = lookup(cors_rule.value, "allowed_headers", ["*"])
      allowed_methods = cors_rule.value.allowed_methods
      allowed_origins = cors_rule.value.allowed_origins
      expose_headers  = lookup(cors_rule.value, "expose_headers", [])
      max_age_seconds = lookup(cors_rule.value, "max_age_seconds", 3600)
    }
  }
}

# 日志配置
resource "aws_s3_bucket_logging" "this" {
  count = var.enable_logging ? 1 : 0

  bucket = aws_s3_bucket.this.id

  target_bucket = var.logging_target_bucket
  target_prefix = var.logging_target_prefix != null ? var.logging_target_prefix : "${var.bucket_name}/"
}

# 事件通知配置
resource "aws_s3_bucket_notification" "this" {
  count = length(var.event_notifications) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  dynamic "lambda_function" {
    for_each = [for n in var.event_notifications : n if n.type == "lambda"]

    content {
      id                  = lambda_function.value.id
      lambda_function_arn = lambda_function.value.arn
      events              = lambda_function.value.events
      filter_prefix       = lookup(lambda_function.value, "filter_prefix", null)
      filter_suffix       = lookup(lambda_function.value, "filter_suffix", null)
    }
  }

  dynamic "sns_topic" {
    for_each = [for n in var.event_notifications : n if n.type == "sns"]

    content {
      id            = sns_topic.value.id
      topic_arn     = sns_topic.value.arn
      events        = sns_topic.value.events
      filter_prefix = lookup(sns_topic.value, "filter_prefix", null)
      filter_suffix = lookup(sns_topic.value, "filter_suffix", null)
    }
  }

  dynamic "sqs_queue" {
    for_each = [for n in var.event_notifications : n if n.type == "sqs"]

    content {
      id            = sqs_queue.value.id
      queue_arn     = sqs_queue.value.arn
      events        = sqs_queue.value.events
      filter_prefix = lookup(sqs_queue.value, "filter_prefix", null)
      filter_suffix = lookup(sqs_queue.value, "filter_suffix", null)
    }
  }
}

# 智能分层配置
resource "aws_s3_bucket_intelligent_tiering_configuration" "this" {
  count = var.enable_intelligent_tiering ? 1 : 0

  bucket = aws_s3_bucket.this.id
  name   = "${var.bucket_name}-intelligent-tiering"

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = 180
  }

  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 90
  }
}

# 桶策略
resource "aws_s3_bucket_policy" "this" {
  count = var.bucket_policy != null ? 1 : 0

  bucket = aws_s3_bucket.this.id
  policy = var.bucket_policy
}

# 网站配置
resource "aws_s3_bucket_website_configuration" "this" {
  count = var.enable_website_hosting ? 1 : 0

  bucket = aws_s3_bucket.this.id

  index_document {
    suffix = var.website_index_document
  }

  error_document {
    key = var.website_error_document
  }

  dynamic "routing_rule" {
    for_each = var.website_routing_rules

    content {
      condition {
        http_error_code_returned_equals = lookup(routing_rule.value, "condition_http_error_code", null)
        key_prefix_equals               = lookup(routing_rule.value, "condition_key_prefix", null)
      }

      redirect {
        host_name               = lookup(routing_rule.value, "redirect_host_name", null)
        http_redirect_code      = lookup(routing_rule.value, "redirect_http_code", null)
        protocol                = lookup(routing_rule.value, "redirect_protocol", null)
        replace_key_prefix_with = lookup(routing_rule.value, "redirect_replace_key_prefix", null)
        replace_key_with        = lookup(routing_rule.value, "redirect_replace_key", null)
      }
    }
  }
}

# 加速配置
resource "aws_s3_bucket_accelerate_configuration" "this" {
  count = var.enable_acceleration ? 1 : 0

  bucket = aws_s3_bucket.this.id
  status = "Enabled"
}

# 库存配置
resource "aws_s3_bucket_inventory" "this" {
  count = var.enable_inventory ? 1 : 0

  bucket = aws_s3_bucket.this.id
  name   = "${var.bucket_name}-inventory"

  included_object_versions = "All"

  schedule {
    frequency = var.inventory_frequency
  }

  destination {
    bucket {
      format     = "CSV"
      bucket_arn = var.inventory_destination_bucket_arn
      prefix     = var.inventory_destination_prefix

      encryption {
        sse_s3 {
          # SSE-S3 加密
        }
      }
    }
  }

  optional_fields = [
    "Size",
    "LastModifiedDate",
    "StorageClass",
    "ETag",
    "IsMultipartUploaded",
    "ReplicationStatus",
    "EncryptionStatus"
  ]
}