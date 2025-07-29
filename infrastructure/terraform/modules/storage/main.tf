# Document Storage S3 Bucket
resource "aws_s3_bucket" "documents" {
  bucket        = "${var.project_name}-documents-${var.environment}-${var.random_suffix}"
  force_destroy = true

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-documents-${var.environment}"
      Type = "DocumentStorage"
    }
  )
}

# Document Bucket Versioning
resource "aws_s3_bucket_versioning" "documents" {
  bucket = aws_s3_bucket.documents.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Disabled"
  }
}

# Document Bucket Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  count  = var.enable_encryption ? 1 : 0
  bucket = aws_s3_bucket.documents.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Document Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "documents" {
  bucket = aws_s3_bucket.documents.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Document Bucket CORS Configuration
resource "aws_s3_bucket_cors_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag", "x-amz-server-side-encryption", "x-amz-request-id", "x-amz-id-2"]
    max_age_seconds = 3000
  }
}

# Document Bucket Lifecycle Policy
resource "aws_s3_bucket_lifecycle_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id

  rule {
    id     = "archive-old-documents"
    status = "Enabled"

    filter {}

    transition {
      days          = var.lifecycle_glacier_transition_days
      storage_class = "GLACIER"
    }

    expiration {
      days = var.lifecycle_expiration_days
    }
  }
}

# Frontend Storage S3 Bucket
resource "aws_s3_bucket" "frontend" {
  bucket        = "${var.project_name}-frontend-${var.environment}-${var.random_suffix}"
  force_destroy = true

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-frontend-${var.environment}"
      Type = "FrontendStorage"
    }
  )
}

# Frontend Bucket Website Configuration
resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

# Frontend Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Frontend Bucket CORS Configuration
resource "aws_s3_bucket_cors_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# Lambda Deployment S3 Bucket
resource "aws_s3_bucket" "lambda_deployments" {
  bucket        = "${var.project_name}-lambda-deployments-${var.environment}-${var.random_suffix}"
  force_destroy = true

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-lambda-deployments-${var.environment}"
      Type = "LambdaDeployments"
    }
  )
}

# Lambda Deployment Bucket Versioning
resource "aws_s3_bucket_versioning" "lambda_deployments" {
  bucket = aws_s3_bucket.lambda_deployments.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Lambda Deployment Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "lambda_deployments" {
  bucket = aws_s3_bucket.lambda_deployments.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lambda Deployment Bucket Lifecycle Policy
resource "aws_s3_bucket_lifecycle_configuration" "lambda_deployments" {
  bucket = aws_s3_bucket.lambda_deployments.id

  rule {
    id     = "cleanup-old-deployments"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}
# S3 Event Notification for Document Uploads
resource "aws_s3_bucket_notification" "documents" {
  count  = var.enable_s3_notifications && var.document_processor_lambda_name != "" ? 1 : 0
  bucket = aws_s3_bucket.documents.id

  lambda_function {
    id                  = var.s3_notification_id
    lambda_function_arn = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.document_processor_lambda_name}"
    events              = var.s3_notification_events
    filter_prefix       = var.document_prefix
  }

  depends_on = [aws_lambda_permission.allow_s3_invoke]
}

# Data source to get AWS account ID
data "aws_caller_identity" "current" {}

# Lambda Permission for S3 to invoke the function
resource "aws_lambda_permission" "allow_s3_invoke" {
  count         = var.enable_s3_notifications && var.document_processor_lambda_name != "" ? 1 : 0
  statement_id  = var.lambda_permission_statement_id
  action        = "lambda:InvokeFunction"
  function_name = var.document_processor_lambda_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.documents.arn
}
