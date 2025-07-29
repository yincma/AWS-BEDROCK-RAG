# 基本配置
variable "function_name" {
  description = "Lambda 函数名称"
  type        = string
}

variable "description" {
  description = "Lambda 函数描述"
  type        = string
  default     = ""
}

variable "tags" {
  description = "资源标签"
  type        = map(string)
  default     = {}
}

# 部署包配置
variable "deployment_package_type" {
  description = "部署包类型: zip, s3, 或 container"
  type        = string
  default     = "zip"

  validation {
    condition     = contains(["zip", "s3", "container"], var.deployment_package_type)
    error_message = "部署包类型必须是: zip, s3, 或 container"
  }
}

variable "filename" {
  description = "本地 ZIP 文件路径"
  type        = string
  default     = null
}

variable "s3_bucket" {
  description = "S3 桶名称"
  type        = string
  default     = null
}

variable "s3_key" {
  description = "S3 对象键"
  type        = string
  default     = null
}

variable "s3_object_version" {
  description = "S3 对象版本"
  type        = string
  default     = null
}

variable "container_image_uri" {
  description = "容器镜像 URI"
  type        = string
  default     = null
}

variable "source_code_hash" {
  description = "源代码哈希值"
  type        = string
  default     = null
}

# 运行时配置
variable "runtime" {
  description = "Lambda 运行时"
  type        = string
  default     = "python3.9"
}

variable "handler" {
  description = "Lambda 处理程序"
  type        = string
  default     = "index.handler"
}

variable "architecture" {
  description = "指令集架构: x86_64 或 arm64"
  type        = string
  default     = "x86_64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "架构必须是: x86_64 或 arm64"
  }
}

# 执行配置
variable "role_arn" {
  description = "Lambda 执行角色 ARN"
  type        = string
}

variable "timeout" {
  description = "超时时间（秒）"
  type        = number
  default     = 60
}

variable "memory_size" {
  description = "内存大小（MB）"
  type        = number
  default     = 512
}

variable "reserved_concurrent_executions" {
  description = "预留并发执行数"
  type        = number
  default     = null
}

variable "provisioned_concurrent_executions" {
  description = "预配置并发执行数"
  type        = number
  default     = 0
}

# 环境变量
variable "environment_variables" {
  description = "环境变量"
  type        = map(string)
  default     = {}
}

# VPC 配置
variable "vpc_config" {
  description = "VPC 配置"
  type = object({
    subnet_ids         = list(string)
    security_group_ids = list(string)
  })
  default = null
}

# EFS 配置
variable "efs_mount_configs" {
  description = "EFS 挂载配置列表"
  type = list(object({
    efs_access_point_arn = string
    local_mount_path     = string
  }))
  default = []
}

# 死信队列配置
variable "dead_letter_config" {
  description = "死信队列配置"
  type = object({
    target_arn = string
  })
  default = null
}

# 追踪配置
variable "tracing_mode" {
  description = "X-Ray 追踪模式: Active 或 PassThrough"
  type        = string
  default     = "Active"

  validation {
    condition     = contains(["Active", "PassThrough"], var.tracing_mode)
    error_message = "追踪模式必须是: Active 或 PassThrough"
  }
}

# 容器镜像配置
variable "image_config" {
  description = "容器镜像配置"
  type = object({
    command           = optional(list(string))
    entry_point       = optional(list(string))
    working_directory = optional(string)
  })
  default = null
}

# 临时存储配置
variable "ephemeral_storage_size" {
  description = "临时存储大小（MB），512-10240"
  type        = number
  default     = null
}

# SnapStart 配置
variable "enable_snap_start" {
  description = "是否启用 SnapStart"
  type        = bool
  default     = false
}

# 运行时管理配置
variable "runtime_management_config" {
  description = "运行时管理配置"
  type = object({
    update_runtime_on   = optional(string, "Auto")
    runtime_version_arn = optional(string)
  })
  default = {
    update_runtime_on = "Auto"
  }
}

# 日志配置
variable "logging_config" {
  description = "日志配置"
  type = object({
    log_format            = optional(string, "Text")
    log_group             = optional(string)
    system_log_level      = optional(string, "INFO")
    application_log_level = optional(string, "INFO")
  })
  default = {
    log_format = "Text"
  }
}

variable "log_retention_days" {
  description = "CloudWatch 日志保留天数"
  type        = number
  default     = 7
}

variable "logs_kms_key_id" {
  description = "CloudWatch 日志 KMS 密钥 ID"
  type        = string
  default     = null
}

# Lambda 层
variable "layers" {
  description = "要附加到 Lambda 函数的层 ARN 列表"
  type        = list(string)
  default     = []
}

# Lambda 层创建配置
variable "layer_configs" {
  description = "Lambda 层创建配置"
  type = map(object({
    description              = optional(string)
    filename                 = optional(string)
    s3_bucket                = optional(string)
    s3_key                   = optional(string)
    s3_object_version        = optional(string)
    source_code_hash         = optional(string)
    compatible_runtimes      = optional(list(string))
    compatible_architectures = optional(list(string))
    license_info             = optional(string)
  }))
  default = {}
}

# 函数 URL
variable "create_function_url" {
  description = "是否创建函数 URL"
  type        = bool
  default     = false
}

variable "function_url_config" {
  description = "函数 URL 配置"
  type = object({
    authorization_type = optional(string, "AWS_IAM")
    cors = optional(object({
      allow_credentials = optional(bool)
      allow_headers     = optional(list(string))
      allow_methods     = optional(list(string))
      allow_origins     = optional(list(string))
      expose_headers    = optional(list(string))
      max_age           = optional(number)
    }))
    qualifier = optional(string)
  })
  default = {
    authorization_type = "AWS_IAM"
  }
}

# 别名配置
variable "create_alias" {
  description = "是否创建别名"
  type        = bool
  default     = false
}

variable "alias_name" {
  description = "别名名称"
  type        = string
  default     = "live"
}

variable "alias_description" {
  description = "别名描述"
  type        = string
  default     = ""
}

variable "publish" {
  description = "是否发布新版本"
  type        = bool
  default     = false
}

variable "alias_routing_config" {
  description = "别名路由配置"
  type = object({
    additional_version_weights = map(number)
  })
  default = null
}

# 权限配置
variable "lambda_permissions" {
  description = "Lambda 权限配置"
  type = map(object({
    action             = optional(string, "lambda:InvokeFunction")
    principal          = string
    source_arn         = optional(string)
    source_account     = optional(string)
    qualifier          = optional(string)
    event_source_token = optional(string)
  }))
  default = {}
}

# 事件源映射
variable "event_source_mappings" {
  description = "事件源映射配置"
  type = map(object({
    event_source_arn                   = string
    enabled                            = optional(bool, true)
    batch_size                         = optional(number)
    maximum_batching_window_in_seconds = optional(number)
    parallelization_factor             = optional(number)
    starting_position                  = optional(string)
    starting_position_timestamp        = optional(string)
    bisect_batch_on_function_error     = optional(bool)
    maximum_retry_attempts             = optional(number)
    maximum_record_age_in_seconds      = optional(number)
    tumbling_window_in_seconds         = optional(number)
    destination_config = optional(object({
      on_failure = optional(object({
        destination_arn = string
      }))
    }))
    filter_criteria = optional(object({
      filters = list(object({
        pattern = string
      }))
    }))
    self_managed_event_source = optional(object({
      endpoints = map(list(string))
    }))
    source_access_configurations = optional(list(object({
      type = string
      uri  = string
    })))
  }))
  default = {}
}

# 异步调用配置
variable "async_invoke_config" {
  description = "异步调用配置"
  type = object({
    maximum_event_age_in_seconds = optional(number)
    maximum_retry_attempts       = optional(number)
    destination_config = optional(object({
      on_success = optional(object({
        destination = string
      }))
      on_failure = optional(object({
        destination = string
      }))
    }))
  })
  default = null
}

# 项目和环境配置
variable "project_name" {
  description = "项目名称"
  type        = string
  default     = "rag-system"
}

variable "environment" {
  description = "环境名称"
  type        = string
  default     = "dev"
}

variable "common_tags" {
  description = "通用标签"
  type        = map(string)
  default     = {}
}

variable "enable_provisioned_concurrency" {
  description = "是否启用预配置并发"
  type        = bool
  default     = false
}

variable "enable_cold_start_optimization" {
  description = "是否启用冷启动优化"
  type        = bool
  default     = false
}

variable "aws_region" {
  description = "AWS区域"
  type        = string
  default     = "us-east-1"
}

