# Lambda Module - 增强的 Lambda 函数部署模块

# Lambda 函数
resource "aws_lambda_function" "this" {
  function_name = var.function_name
  description   = var.description

  # 部署包配置
  filename          = var.deployment_package_type == "zip" ? var.filename : null
  s3_bucket         = var.deployment_package_type == "s3" ? var.s3_bucket : null
  s3_key            = var.deployment_package_type == "s3" ? var.s3_key : null
  s3_object_version = var.deployment_package_type == "s3" ? var.s3_object_version : null
  image_uri         = var.deployment_package_type == "container" ? var.container_image_uri : null

  package_type = var.deployment_package_type == "container" ? "Image" : "Zip"

  # 运行时配置
  runtime          = var.deployment_package_type != "container" ? var.runtime : null
  handler          = var.deployment_package_type != "container" ? var.handler : null
  source_code_hash = var.deployment_package_type == "zip" ? var.source_code_hash : null

  # 执行配置
  role                           = var.role_arn
  timeout                        = var.timeout
  memory_size                    = var.memory_size
  reserved_concurrent_executions = var.reserved_concurrent_executions

  # 架构
  architectures = [var.architecture]

  # Lambda 层
  layers = var.layers

  # 环境变量
  dynamic "environment" {
    for_each = length(var.environment_variables) > 0 ? [1] : []

    content {
      variables = var.environment_variables
    }
  }

  # VPC 配置
  dynamic "vpc_config" {
    for_each = var.vpc_config != null ? [var.vpc_config] : []

    content {
      subnet_ids         = vpc_config.value.subnet_ids
      security_group_ids = vpc_config.value.security_group_ids
    }
  }

  # 文件系统配置（EFS）
  dynamic "file_system_config" {
    for_each = var.efs_mount_configs

    content {
      arn              = file_system_config.value.efs_access_point_arn
      local_mount_path = file_system_config.value.local_mount_path
    }
  }

  # 死信队列配置
  dynamic "dead_letter_config" {
    for_each = var.dead_letter_config != null ? [var.dead_letter_config] : []

    content {
      target_arn = dead_letter_config.value.target_arn
    }
  }

  # 追踪配置
  dynamic "tracing_config" {
    for_each = var.tracing_mode != null ? [1] : []

    content {
      mode = var.tracing_mode
    }
  }

  # 镜像配置（容器部署）
  dynamic "image_config" {
    for_each = var.deployment_package_type == "container" && var.image_config != null ? [var.image_config] : []

    content {
      command           = lookup(image_config.value, "command", null)
      entry_point       = lookup(image_config.value, "entry_point", null)
      working_directory = lookup(image_config.value, "working_directory", null)
    }
  }

  # Ephemeral 存储配置
  dynamic "ephemeral_storage" {
    for_each = var.ephemeral_storage_size != null ? [1] : []

    content {
      size = var.ephemeral_storage_size
    }
  }

  # 快照配置
  dynamic "snap_start" {
    for_each = var.enable_snap_start ? [1] : []

    content {
      apply_on = "PublishedVersions"
    }
  }


  tags = merge(
    var.tags,
    {
      Name = var.function_name
    }
  )

  depends_on = [aws_cloudwatch_log_group.this]
}

# CloudWatch 日志组
resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_id

  tags = var.tags
}

# Lambda 层
resource "aws_lambda_layer_version" "this" {
  for_each = var.layer_configs

  layer_name        = each.key
  description       = each.value.description
  filename          = each.value.filename
  s3_bucket         = each.value.s3_bucket
  s3_key            = each.value.s3_key
  s3_object_version = each.value.s3_object_version
  source_code_hash  = each.value.source_code_hash

  compatible_runtimes      = each.value.compatible_runtimes
  compatible_architectures = each.value.compatible_architectures

  license_info = each.value.license_info
}

# 函数 URL
resource "aws_lambda_function_url" "this" {
  count = var.create_function_url ? 1 : 0

  function_name      = aws_lambda_function.this.function_name
  authorization_type = var.function_url_config.authorization_type

  dynamic "cors" {
    for_each = var.function_url_config.cors != null ? [var.function_url_config.cors] : []

    content {
      allow_credentials = lookup(cors.value, "allow_credentials", false)
      allow_headers     = lookup(cors.value, "allow_headers", ["*"])
      allow_methods     = lookup(cors.value, "allow_methods", ["*"])
      allow_origins     = lookup(cors.value, "allow_origins", ["*"])
      expose_headers    = lookup(cors.value, "expose_headers", [])
      max_age           = lookup(cors.value, "max_age", 0)
    }
  }

  qualifier = var.function_url_config.qualifier
}

# 预留并发
resource "aws_lambda_provisioned_concurrency_config" "this" {
  count = var.provisioned_concurrent_executions > 0 && var.create_alias ? 1 : 0

  function_name                     = aws_lambda_function.this.function_name
  provisioned_concurrent_executions = var.provisioned_concurrent_executions
  qualifier                         = aws_lambda_alias.live[0].name

  depends_on = [aws_lambda_alias.live]
}

# Lambda 别名
resource "aws_lambda_alias" "live" {
  count = var.create_alias ? 1 : 0

  name             = var.alias_name
  description      = var.alias_description
  function_name    = aws_lambda_function.this.function_name
  function_version = var.publish ? aws_lambda_function.this.version : "$LATEST"

  dynamic "routing_config" {
    for_each = var.alias_routing_config != null ? [var.alias_routing_config] : []

    content {
      additional_version_weights = routing_config.value.additional_version_weights
    }
  }
}

# 权限配置
resource "aws_lambda_permission" "this" {
  for_each = var.lambda_permissions

  statement_id       = each.key
  action             = each.value.action
  function_name      = aws_lambda_function.this.function_name
  principal          = each.value.principal
  source_arn         = lookup(each.value, "source_arn", null)
  source_account     = lookup(each.value, "source_account", null)
  qualifier          = lookup(each.value, "qualifier", null)
  event_source_token = lookup(each.value, "event_source_token", null)
}

# 事件源映射
resource "aws_lambda_event_source_mapping" "this" {
  for_each = var.event_source_mappings

  function_name    = var.create_alias ? aws_lambda_alias.live[0].arn : aws_lambda_function.this.arn
  event_source_arn = each.value.event_source_arn

  # 基本配置
  enabled                            = lookup(each.value, "enabled", true)
  batch_size                         = lookup(each.value, "batch_size", null)
  maximum_batching_window_in_seconds = lookup(each.value, "maximum_batching_window_in_seconds", null)
  parallelization_factor             = lookup(each.value, "parallelization_factor", null)
  starting_position                  = lookup(each.value, "starting_position", null)
  starting_position_timestamp        = lookup(each.value, "starting_position_timestamp", null)

  # 错误处理
  bisect_batch_on_function_error = lookup(each.value, "bisect_batch_on_function_error", false)
  maximum_retry_attempts         = lookup(each.value, "maximum_retry_attempts", null)
  maximum_record_age_in_seconds  = lookup(each.value, "maximum_record_age_in_seconds", null)
  tumbling_window_in_seconds     = lookup(each.value, "tumbling_window_in_seconds", null)

  # 目标配置
  dynamic "destination_config" {
    for_each = lookup(each.value, "destination_config", null) != null ? [each.value.destination_config] : []

    content {
      dynamic "on_failure" {
        for_each = lookup(destination_config.value, "on_failure", null) != null ? [destination_config.value.on_failure] : []

        content {
          destination_arn = on_failure.value.destination_arn
        }
      }
    }
  }

  # 过滤条件
  dynamic "filter_criteria" {
    for_each = lookup(each.value, "filter_criteria", null) != null ? [each.value.filter_criteria] : []

    content {
      dynamic "filter" {
        for_each = filter_criteria.value.filters

        content {
          pattern = filter.value.pattern
        }
      }
    }
  }

  # 自托管 Kafka
  dynamic "self_managed_event_source" {
    for_each = lookup(each.value, "self_managed_event_source", null) != null ? [each.value.self_managed_event_source] : []

    content {
      endpoints = self_managed_event_source.value.endpoints
    }
  }

  # 源访问配置
  dynamic "source_access_configuration" {
    for_each = lookup(each.value, "source_access_configurations", [])

    content {
      type = source_access_configuration.value.type
      uri  = source_access_configuration.value.uri
    }
  }
}

# 异步调用配置
resource "aws_lambda_function_event_invoke_config" "this" {
  count = var.async_invoke_config != null ? 1 : 0

  function_name                = aws_lambda_function.this.function_name
  qualifier                    = var.create_alias ? aws_lambda_alias.live[0].name : null
  maximum_event_age_in_seconds = var.async_invoke_config.maximum_event_age_in_seconds
  maximum_retry_attempts       = var.async_invoke_config.maximum_retry_attempts

  dynamic "destination_config" {
    for_each = var.async_invoke_config.destination_config != null ? [var.async_invoke_config.destination_config] : []

    content {
      dynamic "on_success" {
        for_each = destination_config.value.on_success != null ? [destination_config.value.on_success] : []

        content {
          destination = on_success.value.destination
        }
      }

      dynamic "on_failure" {
        for_each = destination_config.value.on_failure != null ? [destination_config.value.on_failure] : []

        content {
          destination = on_failure.value.destination
        }
      }
    }
  }
}