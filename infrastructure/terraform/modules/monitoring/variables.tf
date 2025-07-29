# 监控模块变量定义

variable "project_name" {
  description = "项目名称"
  type        = string
}

variable "environment" {
  description = "环境名称"
  type        = string
}

variable "aws_region" {
  description = "AWS区域"
  type        = string
  default     = "us-east-1"
}

variable "common_tags" {
  description = "通用标签"
  type        = map(string)
  default     = {}
}

variable "alarm_email" {
  description = "告警通知邮箱"
  type        = string
  default     = ""
}

variable "api_gateway_name" {
  description = "API Gateway名称"
  type        = string
}

variable "api_gateway_stage" {
  description = "API Gateway阶段"
  type        = string
}

variable "lambda_functions" {
  description = "要监控的Lambda函数列表"
  type        = list(string)
}

variable "cost_alert_threshold" {
  description = "成本告警阈值（USD）"
  type        = number
  default     = 500
}

variable "enable_xray_tracing" {
  description = "是否启用X-Ray追踪"
  type        = bool
  default     = true
}

variable "enable_synthetics" {
  description = "是否启用Synthetics监控"
  type        = bool
  default     = false
}

variable "monitoring_bucket" {
  description = "监控数据存储桶"
  type        = string
  default     = ""
}

variable "api_endpoint" {
  description = "API端点URL（用于Synthetics）"
  type        = string
  default     = ""
}