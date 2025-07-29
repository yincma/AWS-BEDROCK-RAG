# API Gateway Performance Optimization Module
# 实现缓存、CloudFront分发、限流和响应压缩

# API Gateway 缓存配置
resource "aws_api_gateway_method_settings" "cache_settings" {
  for_each = var.api_cache_config

  rest_api_id = each.value.rest_api_id
  stage_name  = each.value.stage_name
  method_path = each.value.method_path

  settings {
    # 缓存配置
    caching_enabled                         = each.value.cache_enabled
    cache_ttl_in_seconds                    = each.value.cache_ttl
    cache_data_encrypted                    = each.value.cache_encrypted
    require_authorization_for_cache_control = each.value.require_auth_for_cache

    # 限流配置
    throttling_rate_limit  = each.value.rate_limit
    throttling_burst_limit = each.value.burst_limit

    # 日志配置
    logging_level      = "INFO"
    data_trace_enabled = var.enable_data_trace
    metrics_enabled    = true
  }
}

# API Gateway 使用计划（限流）
resource "aws_api_gateway_usage_plan" "rate_limiting" {
  name        = "${var.api_name}-usage-plan"
  description = "Usage plan with rate limiting for ${var.api_name}"

  api_stages {
    api_id = var.rest_api_id
    stage  = var.stage_name
  }

  quota_settings {
    limit  = var.quota_limit
    period = var.quota_period
  }

  throttle_settings {
    rate_limit  = var.default_rate_limit
    burst_limit = var.default_burst_limit
  }
}

# API Gateway API密钥
resource "aws_api_gateway_api_key" "api_key" {
  count = var.enable_api_key ? 1 : 0

  name        = "${var.api_name}-api-key"
  description = "API key for ${var.api_name}"
  enabled     = true
}

# API密钥与使用计划关联
resource "aws_api_gateway_usage_plan_key" "api_key_association" {
  count = var.enable_api_key ? 1 : 0

  key_id        = aws_api_gateway_api_key.api_key[0].id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.rate_limiting.id
}

# CloudFront 分发配置
resource "aws_cloudfront_distribution" "api_cdn" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "${var.api_name} CloudFront distribution"
  price_class     = var.cloudfront_price_class

  origin {
    domain_name = "${var.rest_api_id}.execute-api.${data.aws_region.current.name}.amazonaws.com"
    origin_id   = "APIGateway-${var.rest_api_id}"
    origin_path = "/${var.stage_name}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]

      # 保持连接时间优化
      origin_keepalive_timeout = 60
      origin_read_timeout      = 30
    }
  }

  # 默认缓存行为
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "APIGateway-${var.rest_api_id}"

    forwarded_values {
      query_string = true
      headers      = var.cloudfront_forwarded_headers

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = var.cloudfront_default_ttl
    max_ttl                = var.cloudfront_max_ttl

    # 压缩配置
    compress = true
  }

  # 针对不同路径的缓存行为
  dynamic "ordered_cache_behavior" {
    for_each = var.cache_behaviors

    content {
      path_pattern     = ordered_cache_behavior.value.path_pattern
      allowed_methods  = ordered_cache_behavior.value.allowed_methods
      cached_methods   = ordered_cache_behavior.value.cached_methods
      target_origin_id = "APIGateway-${var.rest_api_id}"

      forwarded_values {
        query_string = ordered_cache_behavior.value.forward_query_string
        headers      = ordered_cache_behavior.value.forwarded_headers

        cookies {
          forward = ordered_cache_behavior.value.forward_cookies
        }
      }

      viewer_protocol_policy = "redirect-to-https"
      min_ttl                = ordered_cache_behavior.value.min_ttl
      default_ttl            = ordered_cache_behavior.value.default_ttl
      max_ttl                = ordered_cache_behavior.value.max_ttl
      compress               = true
    }
  }

  # 错误页面缓存
  dynamic "custom_error_response" {
    for_each = var.custom_error_responses

    content {
      error_code            = custom_error_response.value.error_code
      error_caching_min_ttl = custom_error_response.value.caching_min_ttl
      response_code         = custom_error_response.value.response_code
      response_page_path    = custom_error_response.value.response_page_path
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = var.tags
}

# WAF Web ACL for API Protection
resource "aws_wafv2_web_acl" "api_protection" {
  count = var.enable_waf ? 1 : 0

  name  = "${var.api_name}-waf-acl"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # 速率限制规则
  rule {
    name     = "RateLimitRule"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.api_name}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  # SQL注入防护
  rule {
    name     = "SQLInjectionRule"
    priority = 2

    action {
      block {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.api_name}-sql-injection"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.api_name}-waf"
    sampled_requests_enabled   = true
  }

  tags = var.tags
}

# CloudFront与WAF关联
resource "aws_wafv2_web_acl_association" "cloudfront_waf" {
  count = var.enable_waf ? 1 : 0

  resource_arn = aws_cloudfront_distribution.api_cdn.arn
  web_acl_arn  = aws_wafv2_web_acl.api_protection[0].arn
}

# API Gateway 响应压缩配置
resource "aws_api_gateway_gateway_response" "response_compression" {
  for_each = {
    "DEFAULT_4XX" = "4\\d{2}"
    "DEFAULT_5XX" = "5\\d{2}"
  }

  rest_api_id   = var.rest_api_id
  response_type = each.key

  response_parameters = {
    "gatewayresponse.header.Content-Encoding" = "'gzip'"
  }

  response_templates = {
    "application/json" = jsonencode({
      message   = "$context.error.messageString"
      type      = "$context.error.responseType"
      requestId = "$context.requestId"
    })
  }
}

# CloudWatch 性能监控仪表板
resource "aws_cloudwatch_dashboard" "api_performance" {
  dashboard_name = "${var.api_name}-performance-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ApiGateway", "Latency", { stat = "Average" }],
            ["...", { stat = "p99" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "API Gateway Latency"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ApiGateway", "Count", { stat = "Sum" }],
            [".", "4XXError", { stat = "Sum" }],
            [".", "5XXError", { stat = "Sum" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "API Requests and Errors"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ApiGateway", "CacheHitCount", { stat = "Sum" }],
            [".", "CacheMissCount", { stat = "Sum" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Cache Performance"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/CloudFront", "BytesDownloaded", "DistributionId", aws_cloudfront_distribution.api_cdn.id],
            [".", "BytesUploaded", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = "us-east-1" # CloudFront metrics are in us-east-1
          title   = "CloudFront Data Transfer"
          period  = 300
        }
      }
    ]
  })
}

# 输出性能优化配置
output "api_performance_config" {
  value = {
    api_gateway_cache_enabled  = length(var.api_cache_config) > 0
    cloudfront_distribution_id = aws_cloudfront_distribution.api_cdn.id
    cloudfront_domain_name     = aws_cloudfront_distribution.api_cdn.domain_name
    waf_enabled                = var.enable_waf
    rate_limiting = {
      default_rate_limit  = var.default_rate_limit
      default_burst_limit = var.default_burst_limit
    }
  }
  description = "API performance optimization configuration"
}

# 数据源
data "aws_region" "current" {}

# 变量定义
variable "api_name" {
  description = "API name"
  type        = string
}

variable "rest_api_id" {
  description = "API Gateway REST API ID"
  type        = string
}

variable "stage_name" {
  description = "API Gateway stage name"
  type        = string
}

variable "api_cache_config" {
  description = "API Gateway cache configuration"
  type = map(object({
    rest_api_id            = string
    stage_name             = string
    method_path            = string
    cache_enabled          = bool
    cache_ttl              = number
    cache_encrypted        = bool
    require_auth_for_cache = bool
    rate_limit             = number
    burst_limit            = number
  }))
  default = {}
}

variable "enable_api_key" {
  description = "Enable API key authentication"
  type        = bool
  default     = false
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

variable "default_rate_limit" {
  description = "Default rate limit (requests per second)"
  type        = number
  default     = 100
}

variable "default_burst_limit" {
  description = "Default burst limit"
  type        = number
  default     = 200
}

variable "cloudfront_price_class" {
  description = "CloudFront price class"
  type        = string
  default     = "PriceClass_100"
}

variable "cloudfront_default_ttl" {
  description = "CloudFront default TTL in seconds"
  type        = number
  default     = 300
}

variable "cloudfront_max_ttl" {
  description = "CloudFront maximum TTL in seconds"
  type        = number
  default     = 3600
}

variable "cloudfront_forwarded_headers" {
  description = "Headers to forward to origin"
  type        = list(string)
  default     = ["Authorization", "Origin", "Referer", "Accept", "Content-Type"]
}

variable "cache_behaviors" {
  description = "CloudFront cache behaviors"
  type = list(object({
    path_pattern         = string
    allowed_methods      = list(string)
    cached_methods       = list(string)
    forward_query_string = bool
    forwarded_headers    = list(string)
    forward_cookies      = string
    min_ttl              = number
    default_ttl          = number
    max_ttl              = number
  }))
  default = []
}

variable "custom_error_responses" {
  description = "CloudFront custom error responses"
  type = list(object({
    error_code         = number
    caching_min_ttl    = number
    response_code      = number
    response_page_path = string
  }))
  default = []
}

variable "enable_waf" {
  description = "Enable WAF protection"
  type        = bool
  default     = true
}

variable "waf_rate_limit" {
  description = "WAF rate limit per 5 minutes"
  type        = number
  default     = 10000
}

variable "enable_data_trace" {
  description = "Enable API Gateway data trace logging"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}