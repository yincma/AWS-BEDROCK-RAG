# API Gateway Performance Optimization Configuration

# Enable caching for specific methods
resource "aws_api_gateway_method_settings" "cache_settings" {
  for_each = var.enable_caching ? var.cached_endpoints : {}

  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = aws_api_gateway_stage.main.stage_name
  method_path = each.key

  settings {
    # Caching configuration
    caching_enabled      = true
    cache_ttl_in_seconds = each.value.ttl
    cache_data_encrypted = true

    # Require authorization for cache invalidation
    require_authorization_for_cache_control    = true
    unauthorized_cache_control_header_strategy = "FAIL_WITH_403"

    # Logging and metrics
    logging_level      = var.environment == "prod" ? "ERROR" : "INFO"
    data_trace_enabled = var.environment != "prod"
    metrics_enabled    = true

    # Throttling
    throttling_rate_limit  = each.value.rate_limit
    throttling_burst_limit = each.value.burst_limit
  }

  depends_on = [aws_api_gateway_deployment.main]
}

# Enhanced API Gateway Stage with cache cluster
resource "aws_api_gateway_stage" "optimized" {
  count = var.enable_caching ? 1 : 0

  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = "${var.environment}-cached"

  # Cache cluster configuration
  cache_cluster_enabled = true
  cache_cluster_size    = var.cache_cluster_size

  # Access logging
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_logs.arn
    format = jsonencode({
      requestId          = "$context.requestId"
      extendedRequestId  = "$context.extendedRequestId"
      ip                 = "$context.identity.sourceIp"
      caller             = "$context.identity.caller"
      user               = "$context.identity.user"
      requestTime        = "$context.requestTime"
      httpMethod         = "$context.httpMethod"
      resourcePath       = "$context.resourcePath"
      status             = "$context.status"
      protocol           = "$context.protocol"
      responseLength     = "$context.responseLength"
      error              = "$context.error.message"
      integrationLatency = "$context.integration.latency"
      responseLatency    = "$context.responseLatency"
    })
  }

  # X-Ray tracing
  xray_tracing_enabled = true

  tags = merge(
    var.common_tags,
    {
      Name         = "${var.project_name}-api-${var.environment}-cached"
      CacheEnabled = "true"
    }
  )

  depends_on = [aws_cloudwatch_log_group.api_gateway_logs]
}

# CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "/aws/apigateway/${var.project_name}/${var.environment}"
  retention_in_days = var.log_retention_days[var.environment]
  kms_key_id        = var.kms_key_arn

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-api-logs"
      Type = "API-Gateway-Logs"
    }
  )
}

# API Gateway Usage Plan for rate limiting
resource "aws_api_gateway_usage_plan" "main" {
  name        = "${var.project_name}-${var.environment}-usage-plan"
  description = "Usage plan for ${var.project_name} in ${var.environment}"

  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
    stage  = aws_api_gateway_stage.main.stage_name
  }

  quota_settings {
    limit  = var.quota_limit
    period = var.quota_period
  }

  throttle_settings {
    rate_limit  = var.throttle_rate_limit
    burst_limit = var.throttle_burst_limit
  }
}

# CloudFront Distribution for API Gateway
resource "aws_cloudfront_distribution" "api_cdn" {
  count = var.enable_cloudfront ? 1 : 0

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CDN for ${var.project_name} API"
  default_root_object = ""
  price_class         = var.cloudfront_price_class

  origin {
    domain_name = "${aws_api_gateway_rest_api.main.id}.execute-api.${data.aws_region.current.name}.amazonaws.com"
    origin_id   = "${var.project_name}-api-gateway"
    origin_path = "/${aws_api_gateway_stage.main.stage_name}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]

      # Timeouts
      origin_keepalive_timeout = 5
      origin_read_timeout      = 30
    }

    # Custom headers for API Gateway
    dynamic "custom_header" {
      for_each = var.api_key != null ? [1] : []
      content {
        name  = "x-api-key"
        value = var.api_key
      }
    }
  }

  # Dynamic cache behaviors for different endpoints
  dynamic "ordered_cache_behavior" {
    for_each = var.cloudfront_cache_behaviors
    content {
      path_pattern     = ordered_cache_behavior.value.path_pattern
      target_origin_id = "${var.project_name}-api-gateway"

      allowed_methods = ordered_cache_behavior.value.allowed_methods
      cached_methods  = ordered_cache_behavior.value.cached_methods

      forwarded_values {
        query_string = ordered_cache_behavior.value.forward_query_string
        headers      = ordered_cache_behavior.value.forward_headers

        cookies {
          forward = "none"
        }
      }

      viewer_protocol_policy = "redirect-to-https"
      min_ttl                = ordered_cache_behavior.value.min_ttl
      default_ttl            = ordered_cache_behavior.value.default_ttl
      max_ttl                = ordered_cache_behavior.value.max_ttl
      compress               = true
    }
  }

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "${var.project_name}-api-gateway"

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Accept", "Content-Type", "X-Amz-Date", "X-Api-Key", "X-Amz-Security-Token"]

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = var.cloudfront_default_ttl
    max_ttl                = var.cloudfront_max_ttl
    compress               = true

    # Enable real-time logs
    realtime_log_config_arn = var.enable_realtime_logs ? aws_cloudfront_realtime_log_config.api_logs[0].arn : null
  }

  # Custom error responses
  dynamic "custom_error_response" {
    for_each = var.cloudfront_custom_error_responses
    content {
      error_code            = custom_error_response.value.error_code
      response_code         = custom_error_response.value.response_code
      response_page_path    = custom_error_response.value.response_page_path
      error_caching_min_ttl = custom_error_response.value.error_caching_min_ttl
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = var.geo_restriction_type
      locations        = var.geo_restriction_locations
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.acm_certificate_arn == null
    acm_certificate_arn            = var.acm_certificate_arn
    ssl_support_method             = var.acm_certificate_arn != null ? "sni-only" : null
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  web_acl_id = var.waf_web_acl_id

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-api-cdn"
      Type = "API-CDN"
    }
  )
}

# CloudFront Real-time Logs Configuration
resource "aws_cloudfront_realtime_log_config" "api_logs" {
  count = var.enable_realtime_logs ? 1 : 0

  name = "${var.project_name}-api-realtime-logs"

  endpoint {
    stream_type = "Kinesis"

    kinesis_stream_config {
      role_arn   = aws_iam_role.cloudfront_logs[0].arn
      stream_arn = aws_kinesis_stream.api_logs[0].arn
    }
  }

  fields = [
    "timestamp",
    "c-ip",
    "sc-status",
    "cs-method",
    "cs-uri-stem",
    "x-edge-location",
    "x-edge-request-id",
    "x-host-header",
    "time-taken",
    "cs-protocol",
    "cs-user-agent",
    "x-forwarded-for",
    "ssl-protocol",
    "x-edge-result-type",
    "sc-bytes",
    "x-edge-response-result-type"
  ]

  sampling_rate = var.realtime_logs_sampling_rate
}

# Kinesis Data Stream for real-time logs
resource "aws_kinesis_stream" "api_logs" {
  count = var.enable_realtime_logs ? 1 : 0

  name             = "${var.project_name}-api-logs-stream"
  shard_count      = var.kinesis_shard_count
  retention_period = 24

  encryption_type = "KMS"
  kms_key_id      = var.kms_key_arn

  shard_level_metrics = [
    "IncomingBytes",
    "OutgoingBytes",
    "IncomingRecords",
    "OutgoingRecords"
  ]

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-api-logs-stream"
      Type = "API-Logs-Stream"
    }
  )
}

# IAM Role for CloudFront Logs
resource "aws_iam_role" "cloudfront_logs" {
  count = var.enable_realtime_logs ? 1 : 0

  name = "${var.project_name}-cloudfront-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "cloudfront.amazonaws.com"
      }
    }]
  })

  tags = var.common_tags
}

# IAM Policy for CloudFront Logs
resource "aws_iam_role_policy" "cloudfront_logs" {
  count = var.enable_realtime_logs ? 1 : 0

  name = "${var.project_name}-cloudfront-logs-policy"
  role = aws_iam_role.cloudfront_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "kinesis:PutRecord",
        "kinesis:PutRecords"
      ]
      Resource = aws_kinesis_stream.api_logs[0].arn
    }]
  })
}

# Performance monitoring dashboard
resource "aws_cloudwatch_dashboard" "api_performance" {
  dashboard_name = "${var.project_name}-api-performance"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ApiGateway", "Latency", { stat = "Average" }],
            [".", ".", { stat = "p99" }],
            [".", ".", { stat = "p95" }],
            [".", ".", { stat = "p50" }]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "API Gateway Latency"
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ApiGateway", "CacheHitCount", { stat = "Sum" }],
            [".", "CacheMissCount", { stat = "Sum" }]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Cache Performance"
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ApiGateway", "4XXError", { stat = "Sum" }],
            [".", "5XXError", { stat = "Sum" }]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "API Errors"
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ApiGateway", "Count", { stat = "Sum" }]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Request Count"
        }
      },
      {
        type   = "metric"
        width  = 24
        height = 6
        properties = {
          metrics = [
            ["AWS/CloudFront", "Requests", { stat = "Sum" }],
            [".", "BytesDownloaded", { stat = "Sum" }],
            [".", "BytesUploaded", { stat = "Sum" }]
          ]
          period = 300
          stat   = "Sum"
          region = "us-east-1" # CloudFront metrics are in us-east-1
          title  = "CloudFront Performance"
        }
      }
    ]
  })
}

# CloudWatch Alarms for performance monitoring
resource "aws_cloudwatch_metric_alarm" "api_latency" {
  alarm_name          = "${var.project_name}-api-high-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Latency"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Average"
  threshold           = var.latency_alarm_threshold
  alarm_description   = "This metric monitors API Gateway latency"
  alarm_actions       = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []

  dimensions = {
    ApiName = aws_api_gateway_rest_api.main.name
    Stage   = aws_api_gateway_stage.main.stage_name
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "api_errors" {
  alarm_name          = "${var.project_name}-api-high-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.error_rate_alarm_threshold
  alarm_description   = "This metric monitors API Gateway 5XX errors"
  alarm_actions       = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []

  dimensions = {
    ApiName = aws_api_gateway_rest_api.main.name
    Stage   = aws_api_gateway_stage.main.stage_name
  }

  tags = var.common_tags
}

# Data source for current AWS region
data "aws_region" "current" {}