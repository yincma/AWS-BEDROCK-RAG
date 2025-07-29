# Lambda模块变量定义

variable "function_name" {
  description = "Lambda函数名称"
  type        = string
}

variable "handler" {
  description = "Lambda函数处理器"
  type        = string
}

variable "runtime" {
  description = "Lambda运行时"
  type        = string
  default     = "python3.9"
}

variable "execution_role_arn" {
  description = "Lambda执行角色ARN"
  type        = string
}

variable "deployment_package_path" {
  description = "部署包路径"
  type        = string
  default     = null
}

variable "environment_variables" {
  description = "环境变量"
  type        = map(string)
  default     = {}
}

variable "memory_size" {
  description = "内存大小 (MB)"
  type        = number
  default     = 128
}

variable "timeout" {
  description = "超时时间 (秒)"
  type        = number
  default     = 3
}

variable "reserved_concurrent_executions" {
  description = "预留并发执行数"
  type        = number
  default     = -1
}

variable "layers" {
  description = "Lambda层ARN列表"
  type        = list(string)
  default     = []
}

variable "subnet_ids" {
  description = "子网ID列表（VPC配置）"
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "安全组ID列表（VPC配置）"
  type        = list(string)
  default     = []
}

variable "enable_dlq" {
  description = "是否启用死信队列"
  type        = bool
  default     = true
}

variable "enable_xray" {
  description = "是否启用X-Ray追踪"
  type        = bool
  default     = true
}

variable "enable_alias" {
  description = "是否创建别名"
  type        = bool
  default     = false
}

variable "enable_function_url" {
  description = "是否启用函数URL"
  type        = bool
  default     = false
}

variable "function_url_auth_type" {
  description = "函数URL认证类型"
  type        = string
  default     = "AWS_IAM"
}

variable "function_url_cors" {
  description = "函数URL CORS配置"
  type = object({
    allow_credentials = bool
    allow_origins     = list(string)
    allow_methods     = list(string)
    allow_headers     = list(string)
    expose_headers    = list(string)
    max_age           = number
  })
  default = {
    allow_credentials = false
    allow_origins     = ["*"]
    allow_methods     = ["*"]
    allow_headers     = ["*"]
    expose_headers    = []
    max_age           = 0
  }
}

variable "enable_monitoring" {
  description = "是否启用监控告警"
  type        = bool
  default     = true
}

variable "error_threshold" {
  description = "错误告警阈值"
  type        = number
  default     = 5
}

variable "duration_threshold" {
  description = "执行时间告警阈值 (毫秒)"
  type        = number
  default     = 30000
}

variable "concurrent_executions_threshold" {
  description = "并发执行告警阈值"
  type        = number
  default     = 100
}

variable "alarm_sns_topic_arns" {
  description = "告警SNS主题ARN列表"
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "日志保留天数"
  type        = number
  default     = 7
}

variable "architecture" {
  description = "Lambda架构"
  type        = string
  default     = "x86_64"
}

variable "environment" {
  description = "环境名称"
  type        = string
}

variable "common_tags" {
  description = "通用标签"
  type        = map(string)
  default     = {}
}