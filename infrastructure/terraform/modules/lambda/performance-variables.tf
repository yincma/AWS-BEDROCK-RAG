# Performance Optimization Variables
# Part of PERF-001 implementation

variable "enable_intelligent_warmup" {
  description = "Enable intelligent warm-up orchestrator for Lambda functions"
  type        = bool
  default     = true
}

variable "enable_autoscaling_dashboard" {
  description = "Enable CloudWatch dashboard for auto-scaling monitoring"
  type        = bool
  default     = true
}

variable "target_utilization_percentage" {
  description = "Target utilization percentage for auto-scaling"
  type        = number
  default     = 70

  validation {
    condition     = var.target_utilization_percentage > 0 && var.target_utilization_percentage <= 100
    error_message = "Target utilization must be between 1 and 100."
  }
}

variable "scale_in_cooldown_seconds" {
  description = "Cooldown period for scale-in operations"
  type        = number
  default     = 300 # 5 minutes
}

variable "scale_out_cooldown_seconds" {
  description = "Cooldown period for scale-out operations"
  type        = number
  default     = 60 # 1 minute for faster response
}

variable "enable_scheduled_scaling" {
  description = "Enable scheduled scaling for predictable workloads"
  type        = bool
  default     = true
}

variable "utc_offset" {
  description = "UTC offset for scheduled scaling (e.g., -5 for EST, -8 for PST)"
  type        = number
  default     = -5 # EST by default
}

variable "lambda_function_names" {
  description = "Map of Lambda function names"
  type        = map(string)
  default     = {}
}

variable "lambda_function_arns" {
  description = "Map of Lambda function ARNs"
  type        = map(string)
  default     = {}
}

variable "lambda_function_aliases" {
  description = "Map of Lambda function aliases for provisioned concurrency"
  type        = map(string)
  default     = {}
}

variable "lambda_provisioned_concurrency_configs" {
  description = "Map of provisioned concurrency configurations"
  type        = map(string)
  default     = {}
}

variable "alarm_sns_topic_arns" {
  description = "SNS topic ARNs for alarm notifications"
  type        = list(string)
  default     = []
}

# Performance monitoring thresholds
variable "cold_start_threshold_ms" {
  description = "Threshold for cold start duration alarms (milliseconds)"
  type        = number
  default     = 3000 # 3 seconds
}

variable "memory_utilization_threshold_percent" {
  description = "Threshold for memory utilization alarms (percentage)"
  type        = number
  default     = 85
}

variable "concurrent_execution_threshold" {
  description = "Threshold for concurrent execution alarms"
  type        = number
  default     = 80
}

# Cost optimization settings
variable "enable_cost_optimization" {
  description = "Enable cost optimization features"
  type        = bool
  default     = true
}

variable "graviton2_cost_savings_percent" {
  description = "Expected cost savings from Graviton2 architecture"
  type        = number
  default     = 20
}

# Performance targets
variable "target_cold_start_reduction_percent" {
  description = "Target percentage reduction in cold starts"
  type        = number
  default     = 50
}

variable "target_response_time_reduction_percent" {
  description = "Target percentage reduction in response time"
  type        = number
  default     = 40
}