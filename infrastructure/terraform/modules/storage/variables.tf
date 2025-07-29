variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "random_suffix" {
  description = "Random suffix for unique naming"
  type        = string
}

variable "enable_versioning" {
  description = "Enable versioning for S3 buckets"
  type        = bool
  default     = true
}

variable "enable_encryption" {
  description = "Enable encryption for S3 buckets"
  type        = bool
  default     = true
}

variable "lifecycle_glacier_transition_days" {
  description = "Days before transitioning to Glacier"
  type        = number
  default     = 90
}

variable "lifecycle_expiration_days" {
  description = "Days before expiration"
  type        = number
  default     = 365
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
variable "document_processor_lambda_name" {
  description = "Name of the document processor Lambda function"
  type        = string
  default     = ""
}

variable "enable_s3_notifications" {
  description = "Enable S3 event notifications"
  type        = bool
  default     = true
}

variable "document_prefix" {
  description = "Prefix for document uploads"
  type        = string
  default     = "documents/"
}

variable "s3_notification_events" {
  description = "S3 events that trigger the Lambda function"
  type        = list(string)
  default     = ["s3:ObjectCreated:*"]
}

variable "s3_notification_id" {
  description = "ID for the S3 bucket notification configuration"
  type        = string
  default     = "document-upload-trigger"
}

variable "lambda_permission_statement_id" {
  description = "Statement ID for the Lambda permission"
  type        = string
  default     = "AllowS3Invoke"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}
