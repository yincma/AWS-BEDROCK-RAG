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

variable "frontend_bucket_name" {
  description = "S3 bucket name for frontend"
  type        = string
}

variable "frontend_bucket_arn" {
  description = "S3 bucket ARN for frontend"
  type        = string
}

variable "frontend_bucket_domain_name" {
  description = "S3 bucket domain name for frontend"
  type        = string
}

variable "api_gateway_url" {
  description = "API Gateway URL"
  type        = string
}

variable "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  type        = string
}

variable "cognito_user_pool_client_id" {
  description = "Cognito User Pool Client ID"
  type        = string
}

variable "enable_cloudfront" {
  description = "Enable CloudFront distribution"
  type        = bool
  default     = true
}

variable "cloudfront_price_class" {
  description = "CloudFront price class"
  type        = string
  default     = "PriceClass_100"
}

variable "cloudfront_default_ttl" {
  description = "CloudFront default TTL"
  type        = number
  default     = 86400
}

variable "cloudfront_max_ttl" {
  description = "CloudFront max TTL"
  type        = number
  default     = 31536000
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "api_path_patterns" {
  description = "Path patterns for API endpoints in CloudFront"
  type = object({
    api      = string
    document = string
    query    = string
    upload   = string
    index    = string
  })
  default = {
    api      = "/api/*"
    document = "/document*"
    query    = "/query*"
    upload   = "/upload*"
    index    = "/index/*"
  }
}