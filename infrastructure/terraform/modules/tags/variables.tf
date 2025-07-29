# 基本信息变量
variable "project_name" {
  description = "项目名称"
  type        = string
}

variable "environment" {
  description = "环境名称 (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod", "test", "dr"], var.environment)
    error_message = "环境必须是: dev, staging, prod, test, 或 dr"
  }
}

variable "owner" {
  description = "资源所有者"
  type        = string
}

variable "cost_center" {
  description = "成本中心"
  type        = string
  default     = "Engineering"
}

variable "project_version" {
  description = "项目版本"
  type        = string
  default     = "1.0.0"
}

# 合规性相关变量
variable "enable_compliance_tags" {
  description = "是否启用合规性标签"
  type        = bool
  default     = false
}

variable "data_classification" {
  description = "数据分类级别"
  type        = string
  default     = "Internal"

  validation {
    condition     = contains(["Public", "Internal", "Confidential", "Restricted"], var.data_classification)
    error_message = "数据分类必须是: Public, Internal, Confidential, 或 Restricted"
  }
}

variable "compliance_framework" {
  description = "合规框架"
  type        = string
  default     = "None"
}

variable "backup_required" {
  description = "是否需要备份"
  type        = bool
  default     = true
}

variable "retention_period" {
  description = "数据保留期限（天）"
  type        = string
  default     = "365"
}

# 技术相关变量
variable "enable_technical_tags" {
  description = "是否启用技术标签"
  type        = bool
  default     = true
}

variable "stack_name" {
  description = "技术栈名称"
  type        = string
  default     = "serverless"
}

variable "component_name" {
  description = "组件名称"
  type        = string
  default     = ""
}

variable "deployment_method" {
  description = "部署方法"
  type        = string
  default     = "terraform"
}

variable "monitoring_enabled" {
  description = "是否启用监控"
  type        = bool
  default     = true
}

# 自动化相关变量
variable "enable_automation_tags" {
  description = "是否启用自动化标签"
  type        = bool
  default     = true
}

variable "auto_scaling_enabled" {
  description = "是否启用自动扩展"
  type        = bool
  default     = false
}

variable "auto_shutdown_enabled" {
  description = "是否启用自动关闭"
  type        = bool
  default     = false
}

variable "auto_backup_enabled" {
  description = "是否启用自动备份"
  type        = bool
  default     = false
}

variable "maintenance_window" {
  description = "维护窗口"
  type        = string
  default     = "sun:05:00-sun:07:00"
}

# 额外的自定义标签
variable "additional_tags" {
  description = "额外的自定义标签"
  type        = map(string)
  default     = {}
}