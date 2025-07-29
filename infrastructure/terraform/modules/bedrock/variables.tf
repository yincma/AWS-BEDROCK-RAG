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

variable "document_bucket_name" {
  description = "S3 bucket name for documents"
  type        = string
}

variable "document_bucket_arn" {
  description = "S3 bucket ARN for documents"
  type        = string
}

variable "embedding_model_id" {
  description = "Bedrock embedding model ID"
  type        = string
  default     = "amazon.titan-embed-text-v1"
}

variable "enable_bedrock_knowledge_base" {
  description = "Enable Bedrock Knowledge Base"
  type        = bool
  default     = true
}

variable "opensearch_collection_arn" {
  description = "OpenSearch Serverless collection ARN"
  type        = string
  default     = ""
}

variable "opensearch_collection_endpoint" {
  description = "OpenSearch Serverless collection endpoint"
  type        = string
  default     = ""
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}