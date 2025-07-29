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
}

variable "lambda_function_names" {
  description = "Map of Lambda function names"
  type        = map(string)
}

variable "lambda_function_arns" {
  description = "Map of Lambda function ARNs"
  type        = map(string)
}

variable "lambda_function_invoke_arns" {
  description = "Map of Lambda function invoke ARNs"
  type        = map(string)
}

variable "lambda_source_code_hashes" {
  description = "Map of Lambda function source code hashes"
  type        = map(string)
  default     = {}
}

variable "cognito_user_pool_arn" {
  description = "Cognito User Pool ARN"
  type        = string
}

variable "enable_api_key" {
  description = "Enable API key authentication"
  type        = bool
  default     = false
}

variable "enable_cors" {
  description = "Enable CORS"
  type        = bool
  default     = true
}

variable "cors_allowed_origins" {
  description = "CORS allowed origins"
  type        = list(string)
  default     = ["*"]
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Performance optimization variables
variable "enable_caching" {
  description = "Enable API Gateway caching"
  type        = bool
  default     = false
}

variable "cache_cluster_size" {
  description = "API Gateway cache cluster size"
  type        = string
  default     = "0.5"
}

variable "cached_endpoints" {
  description = "Endpoints to cache with TTL and rate limits"
  type = map(object({
    ttl         = number
    rate_limit  = number
    burst_limit = number
  }))
  default = {}
}

variable "quota_limit" {
  description = "API quota limit"
  type        = number
  default     = 10000
}

variable "quota_period" {
  description = "API quota period"
  type        = string
  default     = "DAY"
}

variable "throttle_rate_limit" {
  description = "API throttle rate limit"
  type        = number
  default     = 100
}

variable "throttle_burst_limit" {
  description = "API throttle burst limit"
  type        = number
  default     = 200
}

variable "enable_cloudfront" {
  description = "Enable CloudFront distribution"
  type        = bool
  default     = false
}

variable "cloudfront_price_class" {
  description = "CloudFront price class"
  type        = string
  default     = "PriceClass_100"
}

variable "cloudfront_default_ttl" {
  description = "CloudFront default TTL"
  type        = number
  default     = 300
}

variable "cloudfront_max_ttl" {
  description = "CloudFront max TTL"
  type        = number
  default     = 3600
}

variable "cloudfront_cache_behaviors" {
  description = "CloudFront cache behaviors configuration"
  type = list(object({
    path_pattern         = string
    allowed_methods      = list(string)
    cached_methods       = list(string)
    forward_query_string = bool
    forward_headers      = list(string)
    min_ttl              = number
    default_ttl          = number
    max_ttl              = number
  }))
  default = []
}

variable "cloudfront_custom_error_responses" {
  description = "CloudFront custom error responses"
  type = list(object({
    error_code            = number
    response_code         = number
    response_page_path    = string
    error_caching_min_ttl = number
  }))
  default = []
}

variable "geo_restriction_type" {
  description = "CloudFront geo restriction type"
  type        = string
  default     = "none"
}

variable "geo_restriction_locations" {
  description = "CloudFront geo restriction locations"
  type        = list(string)
  default     = []
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for CloudFront"
  type        = string
  default     = null
}

variable "waf_web_acl_id" {
  description = "WAF Web ACL ID"
  type        = string
  default     = null
}

variable "api_key" {
  description = "API key for API Gateway"
  type        = string
  sensitive   = true
  default     = null
}

variable "enable_realtime_logs" {
  description = "Enable CloudFront real-time logs"
  type        = bool
  default     = false
}

variable "realtime_logs_sampling_rate" {
  description = "Sampling rate for real-time logs (1-100)"
  type        = number
  default     = 1
}

variable "kinesis_shard_count" {
  description = "Number of Kinesis shards for log stream"
  type        = number
  default     = 1
}

variable "log_retention_days" {
  description = "Log retention days per environment"
  type        = map(number)
  default = {
    dev     = 7
    staging = 30
    prod    = 90
  }
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption"
  type        = string
  default     = null
}

variable "latency_alarm_threshold" {
  description = "Latency alarm threshold in milliseconds"
  type        = number
  default     = 1000
}

variable "error_rate_alarm_threshold" {
  description = "Error rate alarm threshold"
  type        = number
  default     = 10
}

variable "alarm_sns_topic_arn" {
  description = "SNS topic ARN for alarms"
  type        = string
  default     = null
}