# 生成唯一标识符
resource "random_id" "unique" {
  byte_length = 4
}

# CloudFront Origin Access Identity
resource "aws_cloudfront_origin_access_identity" "main" {
  count   = var.enable_cloudfront ? 1 : 0
  comment = "${var.project_name}-${var.environment}"
}

# S3 Bucket Policy for CloudFront
data "aws_iam_policy_document" "frontend_bucket" {
  count = var.enable_cloudfront ? 1 : 0

  statement {
    sid       = "AllowCloudFrontServicePrincipal"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${var.frontend_bucket_arn}/*"]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.main[0].iam_arn]
    }
  }

  # Allow ListBucket for index.html access
  statement {
    sid       = "AllowCloudFrontListBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [var.frontend_bucket_arn]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.main[0].iam_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  count  = var.enable_cloudfront ? 1 : 0
  bucket = var.frontend_bucket_name
  policy = data.aws_iam_policy_document.frontend_bucket[0].json

  depends_on = [
    aws_cloudfront_origin_access_identity.main
  ]
}

# CloudFront Response Headers Policy
resource "aws_cloudfront_response_headers_policy" "security_headers" {
  count = var.enable_cloudfront ? 1 : 0

  name = "${var.project_name}-cf-security-headers-${var.environment}-${random_id.unique.hex}"

  security_headers_config {
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    strict_transport_security {
      access_control_max_age_sec = 63072000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
    content_security_policy {
      content_security_policy = "default-src 'self' https://*.amazonaws.com; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self'; connect-src 'self' https://*.amazonaws.com"
      override                = true
    }
  }

  cors_config {
    access_control_allow_credentials = false
    access_control_allow_headers {
      items = ["*"]
    }
    access_control_allow_methods {
      items = ["GET", "HEAD", "OPTIONS", "POST", "PUT", "DELETE"]
    }
    access_control_allow_origins {
      items = ["*"]
    }
    access_control_max_age_sec = 86400
    origin_override            = true
  }
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "main" {
  count = var.enable_cloudfront ? 1 : 0

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.project_name} ${var.environment} frontend"
  default_root_object = "index.html"
  price_class         = var.cloudfront_price_class

  # S3 Origin for static content
  origin {
    domain_name = var.frontend_bucket_domain_name
    origin_id   = "S3-${var.frontend_bucket_name}"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.main[0].cloudfront_access_identity_path
    }
  }

  # API Gateway Origin for API requests
  origin {
    domain_name = replace(replace(var.api_gateway_url, "https://", ""), "/dev", "")
    origin_id   = "API-Gateway"
    origin_path = "/dev"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Cache behavior for API requests - highest priority
  ordered_cache_behavior {
    path_pattern     = var.api_path_patterns.api
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "API-Gateway"

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Content-Type", "Accept", "Origin", "Access-Control-Request-Method", "Access-Control-Request-Headers", "X-Api-Key"]
      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
    compress               = true
  }

  # Cache behavior for document API
  ordered_cache_behavior {
    path_pattern     = var.api_path_patterns.document
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "API-Gateway"

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Content-Type", "Accept", "Origin", "Access-Control-Request-Method", "Access-Control-Request-Headers", "X-Api-Key"]
      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
    compress               = true
  }

  # Cache behavior for query API
  ordered_cache_behavior {
    path_pattern     = var.api_path_patterns.query
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "API-Gateway"

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Content-Type", "Accept", "Origin", "Access-Control-Request-Method", "Access-Control-Request-Headers", "X-Api-Key"]
      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
    compress               = true
  }

  # Cache behavior for upload API
  ordered_cache_behavior {
    path_pattern     = var.api_path_patterns.upload
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "API-Gateway"

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Content-Type", "Accept", "Origin", "Access-Control-Request-Method", "Access-Control-Request-Headers", "X-Api-Key"]
      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
    compress               = true
  }

  # Cache behavior for index API
  ordered_cache_behavior {
    path_pattern     = var.api_path_patterns.index
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "API-Gateway"

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Content-Type", "Accept", "Origin", "Access-Control-Request-Method", "Access-Control-Request-Headers", "X-Api-Key"]
      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
    compress               = true
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${var.frontend_bucket_name}"

    forwarded_values {
      query_string = true
      cookies {
        forward = "none"
      }
      headers = ["Origin", "Access-Control-Request-Method", "Access-Control-Request-Headers"]
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = var.cloudfront_default_ttl
    max_ttl                = var.cloudfront_max_ttl
    compress               = true

    # Apply security headers policy
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security_headers[0].id
  }

  # Custom error pages for SPA frontend routes only
  # These will only apply to non-API requests since API routes have their own cache behaviors
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-cloudfront-${var.environment}"
    }
  )
}

# Frontend Configuration File
resource "aws_s3_object" "frontend_config" {
  bucket = var.frontend_bucket_name
  key    = "config.json"
  content = jsonencode({
    apiEndpoint      = var.api_gateway_url
    userPoolId       = var.cognito_user_pool_id
    userPoolClientId = var.cognito_user_pool_client_id
    region           = var.aws_region
    environment      = var.environment
  })
  content_type = "application/json"

  etag = md5(jsonencode({
    apiEndpoint      = var.api_gateway_url
    userPoolId       = var.cognito_user_pool_id
    userPoolClientId = var.cognito_user_pool_client_id
    region           = var.aws_region
    environment      = var.environment
  }))

  tags = var.common_tags
}

# CloudWatch Log Group for CloudFront
resource "aws_cloudwatch_log_group" "cloudfront" {
  count             = var.enable_cloudfront ? 1 : 0
  name              = "/aws/cloudfront/${var.project_name}-${var.environment}"
  retention_in_days = 7

  tags = var.common_tags
}