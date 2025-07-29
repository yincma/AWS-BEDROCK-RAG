# Monitoring module variable definitions

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "common_tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}

variable "alarm_email" {
  description = "Alert notification email"
  type        = string
  default     = ""
}

variable "api_gateway_name" {
  description = "API Gateway name"
  type        = string
}

variable "api_gateway_stage" {
  description = "API Gateway stage"
  type        = string
}

variable "lambda_functions" {
  description = "List of Lambda functions to monitor"
  type        = list(string)
}

variable "cost_alert_threshold" {
  description = "Cost alert threshold (USD)"
  type        = number
  default     = 500
}

variable "enable_xray_tracing" {
  description = "Enable X-Ray tracing"
  type        = bool
  default     = true
}

variable "enable_synthetics" {
  description = "Enable Synthetics monitoring"
  type        = bool
  default     = false
}

variable "monitoring_bucket" {
  description = "Monitoring data storage bucket"
  type        = string
  default     = ""
}

variable "api_endpoint" {
  description = "API endpoint URL (for Synthetics)"
  type        = string
  default     = ""
}

# Knowledge Base monitoring
variable "enable_kb_sync_monitoring" {
  description = "Enable Knowledge Base sync monitoring"
  type        = bool
  default     = true
}

variable "knowledge_base_id" {
  description = "Knowledge Base ID"
  type        = string
  default     = ""
}