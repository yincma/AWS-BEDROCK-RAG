# Variables for Logs Optimization Submodule

variable "log_groups" {
  description = "Map of log groups to optimize"
  type        = map(any)
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "enable_metric_filters" {
  description = "Enable metric filters"
  type        = bool
}

variable "enable_subscription_filters" {
  description = "Enable subscription filters"
  type        = bool
}

variable "kms_key_id" {
  description = "KMS key ID for encryption"
  type        = string
  default     = null
}

variable "common_tags" {
  description = "Common tags"
  type        = map(string)
}