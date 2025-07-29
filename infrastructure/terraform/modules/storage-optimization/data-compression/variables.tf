# Variables for Data Compression Submodule

variable "compression_enabled_buckets" {
  description = "Buckets to enable compression"
  type        = map(any)
}

variable "archive_enabled_buckets" {
  description = "Buckets to enable archival"
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

variable "lambda_runtime" {
  description = "Lambda runtime"
  type        = string
}

variable "common_tags" {
  description = "Common tags"
  type        = map(string)
}