output "knowledge_base_id" {
  description = "The ID of the Bedrock Knowledge Base"
  value       = local.knowledge_base_id
}

output "knowledge_base_arn" {
  description = "The ARN of the Bedrock Knowledge Base"
  value       = local.knowledge_base_arn
}

output "data_source_id" {
  description = "The ID of the Bedrock Data Source"
  value       = local.data_source_id
}

output "bedrock_role_arn" {
  description = "The ARN of the Bedrock IAM role"
  value       = var.enable_bedrock_knowledge_base ? aws_iam_role.bedrock_knowledge_base[0].arn : ""
}

output "opensearch_collection_arn" {
  description = "The ARN of the OpenSearch Serverless collection"
  value       = var.enable_bedrock_knowledge_base ? aws_opensearchserverless_collection.knowledge_base[0].arn : ""
}

output "opensearch_collection_endpoint" {
  description = "The endpoint of the OpenSearch Serverless collection"
  value       = local.opensearch_endpoint
}