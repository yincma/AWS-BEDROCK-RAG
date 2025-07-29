# 基本配置
variable "bucket_name" {
  description = "S3 桶名称"
  type        = string
}

variable "bucket_type" {
  description = "桶类型标识（用于标签）"
  type        = string
  default     = "general"
}

variable "tags" {
  description = "资源标签"
  type        = map(string)
  default     = {}
}

# 版本控制
variable "enable_versioning" {
  description = "是否启用版本控制"
  type        = bool
  default     = true
}

# 加密配置
variable "encryption_algorithm" {
  description = "加密算法 (AES256 或 aws:kms)"
  type        = string
  default     = "AES256"

  validation {
    condition     = contains(["AES256", "aws:kms"], var.encryption_algorithm)
    error_message = "加密算法必须是 AES256 或 aws:kms"
  }
}

variable "kms_key_id" {
  description = "KMS 密钥 ID（当使用 aws:kms 加密时）"
  type        = string
  default     = null
}

variable "bucket_key_enabled" {
  description = "是否启用 S3 Bucket Key 以降低 KMS 成本"
  type        = bool
  default     = true
}

# 公共访问
variable "block_public_access" {
  description = "是否阻止公共访问"
  type        = bool
  default     = true
}

# 生命周期规则
variable "lifecycle_rules" {
  description = "生命周期规则列表"
  type = list(object({
    id                                 = string
    enabled                            = bool
    prefix                             = optional(string)
    tags                               = optional(map(string))
    expiration_days                    = optional(number)
    noncurrent_version_expiration_days = optional(number)
    transitions = optional(list(object({
      days          = number
      storage_class = string
    })))
    noncurrent_version_transitions = optional(list(object({
      days          = number
      storage_class = string
    })))
  }))
  default = []
}

# 跨区域复制
variable "enable_replication" {
  description = "是否启用跨区域复制"
  type        = bool
  default     = false
}

variable "replication_role_arn" {
  description = "复制角色 ARN"
  type        = string
  default     = null
}

variable "replication_destination_bucket_arn" {
  description = "复制目标桶 ARN"
  type        = string
  default     = null
}

variable "replication_storage_class" {
  description = "复制存储类别"
  type        = string
  default     = "STANDARD"
}

variable "replication_kms_key_id" {
  description = "复制加密 KMS 密钥 ID"
  type        = string
  default     = null
}

variable "replicate_delete_markers" {
  description = "是否复制删除标记"
  type        = bool
  default     = true
}

# CORS 配置
variable "cors_rules" {
  description = "CORS 规则列表"
  type = list(object({
    id              = optional(string)
    allowed_headers = optional(list(string))
    allowed_methods = list(string)
    allowed_origins = list(string)
    expose_headers  = optional(list(string))
    max_age_seconds = optional(number)
  }))
  default = []
}

# 日志配置
variable "enable_logging" {
  description = "是否启用访问日志"
  type        = bool
  default     = false
}

variable "logging_target_bucket" {
  description = "日志目标桶"
  type        = string
  default     = null
}

variable "logging_target_prefix" {
  description = "日志前缀"
  type        = string
  default     = null
}

# 事件通知
variable "event_notifications" {
  description = "事件通知配置"
  type = list(object({
    id            = string
    type          = string # lambda, sns, or sqs
    arn           = string
    events        = list(string)
    filter_prefix = optional(string)
    filter_suffix = optional(string)
  }))
  default = []
}

# 智能分层
variable "enable_intelligent_tiering" {
  description = "是否启用智能分层"
  type        = bool
  default     = false
}

# 桶策略
variable "bucket_policy" {
  description = "自定义桶策略 JSON"
  type        = string
  default     = null
}

# 网站托管
variable "enable_website_hosting" {
  description = "是否启用静态网站托管"
  type        = bool
  default     = false
}

variable "website_index_document" {
  description = "网站索引文档"
  type        = string
  default     = "index.html"
}

variable "website_error_document" {
  description = "网站错误文档"
  type        = string
  default     = "error.html"
}

variable "website_routing_rules" {
  description = "网站路由规则"
  type        = list(any)
  default     = []
}

# 加速传输
variable "enable_acceleration" {
  description = "是否启用加速传输"
  type        = bool
  default     = false
}

# 库存报告
variable "enable_inventory" {
  description = "是否启用库存报告"
  type        = bool
  default     = false
}

variable "inventory_frequency" {
  description = "库存报告频率 (Daily 或 Weekly)"
  type        = string
  default     = "Weekly"
}

variable "inventory_destination_bucket_arn" {
  description = "库存报告目标桶 ARN"
  type        = string
  default     = null
}

variable "inventory_destination_prefix" {
  description = "库存报告前缀"
  type        = string
  default     = "inventory"
}