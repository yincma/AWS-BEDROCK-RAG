# Variables for Storage Optimization Module

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "s3_buckets" {
  description = "Map of S3 buckets to optimize"
  type = map(object({
    bucket_name                = string
    enable_lifecycle           = optional(bool, true)
    enable_intelligent_tiering = optional(bool, false)
    enable_inventory           = optional(bool, false)
    lifecycle_rules = optional(object({
      ia_transition_days       = optional(number, 30)
      glacier_transition_days  = optional(number, 90)
      deep_archive_days        = optional(number, 180)
      expiration_days          = optional(number, 365)
      log_retention_days       = optional(number, 90)
      enable_multipart_cleanup = optional(bool, true)
      enable_version_cleanup   = optional(bool, true)
    }), {})
    intelligent_tiering_config = optional(object({
      archive_days      = optional(number, 90)
      deep_archive_days = optional(number, 180)
      filter_prefix     = optional(string)
      filter_tags       = optional(map(string))
    }), {})
  }))
  default = {}
}

variable "log_groups" {
  description = "Map of CloudWatch log groups to optimize"
  type = map(object({
    retention_in_days  = optional(number)
    kms_key_id         = optional(string)
    enable_compression = optional(bool, true)
    enable_sampling    = optional(bool, false)
    sampling_rate      = optional(number, 0.1)
    subscription_filter = optional(object({
      filter_pattern  = string
      destination_arn = string
    }))
  }))
  default = {}
}

variable "compression_enabled_buckets" {
  description = "S3 buckets to enable automatic compression"
  type = map(object({
    bucket_name         = string
    compression_types   = optional(list(string), ["gzip", "brotli"])
    file_extensions     = optional(list(string), ["json", "log", "txt", "csv"])
    min_file_size_bytes = optional(number, 1024)
    schedule_expression = optional(string, "rate(1 hour)")
  }))
  default = {}
}

variable "archive_enabled_buckets" {
  description = "S3 buckets to enable automatic archival"
  type = map(object({
    bucket_name          = string
    archive_after_days   = optional(number, 30)
    archive_prefix       = optional(string, "archive/")
    delete_after_archive = optional(bool, false)
  }))
  default = {}
}

variable "enable_intelligent_tiering" {
  description = "Enable S3 Intelligent-Tiering globally"
  type        = bool
  default     = true
}

variable "enable_inventory" {
  description = "Enable S3 Inventory for cost analysis"
  type        = bool
  default     = true
}

variable "enable_storage_lens" {
  description = "Enable S3 Storage Lens for visibility"
  type        = bool
  default     = true
}

variable "enable_metric_filters" {
  description = "Enable CloudWatch metric filters"
  type        = bool
  default     = true
}

variable "enable_subscription_filters" {
  description = "Enable CloudWatch subscription filters"
  type        = bool
  default     = false
}

variable "storage_budget_amount" {
  description = "Monthly budget for S3 storage costs"
  type        = number
  default     = 100
}

variable "logs_budget_amount" {
  description = "Monthly budget for CloudWatch Logs costs"
  type        = number
  default     = 50
}

variable "alert_email" {
  description = "Email address for cost alerts"
  type        = string
  default     = ""
}

variable "kms_key_id" {
  description = "KMS key ID for encryption"
  type        = string
  default     = null
}

variable "lambda_runtime" {
  description = "Lambda runtime for compression functions"
  type        = string
  default     = "python3.9"
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Advanced Configuration Variables

variable "lifecycle_transition_schedule" {
  description = "Custom lifecycle transition schedule"
  type = object({
    dev = object({
      ia_days           = number
      glacier_days      = number
      deep_archive_days = number
      expiration_days   = number
    })
    staging = object({
      ia_days           = number
      glacier_days      = number
      deep_archive_days = number
      expiration_days   = number
    })
    prod = object({
      ia_days           = number
      glacier_days      = number
      deep_archive_days = number
      expiration_days   = number
    })
  })
  default = {
    dev = {
      ia_days           = 7
      glacier_days      = 30
      deep_archive_days = 90
      expiration_days   = 180
    }
    staging = {
      ia_days           = 30
      glacier_days      = 90
      deep_archive_days = 180
      expiration_days   = 365
    }
    prod = {
      ia_days           = 90
      glacier_days      = 180
      deep_archive_days = 365
      expiration_days   = 730
    }
  }
}

variable "compression_settings" {
  description = "Advanced compression settings"
  type = object({
    enable_parallel_processing = optional(bool, true)
    max_concurrent_executions  = optional(number, 10)
    compression_level          = optional(number, 9)
    skip_compressed_files      = optional(bool, true)
  })
  default = {}
}

variable "cost_anomaly_detection" {
  description = "Enable AWS Cost Anomaly Detection"
  type = object({
    enabled              = optional(bool, true)
    threshold_expression = optional(string, "ANOMALY_TOTAL_IMPACT_PERCENTAGE > 20")
    frequency            = optional(string, "DAILY")
  })
  default = {}
}