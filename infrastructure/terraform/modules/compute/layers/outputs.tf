output "opensearch_layer_arn" {
  description = "ARN of the OpenSearch Lambda layer"
  value       = aws_lambda_layer_version.opensearch.arn
}

output "opensearch_layer_version" {
  description = "Version of the OpenSearch Lambda layer"
  value       = aws_lambda_layer_version.opensearch.version
}

output "bedrock_layer_arn" {
  description = "ARN of the Bedrock Lambda layer"
  value       = aws_lambda_layer_version.bedrock.arn
}

output "bedrock_layer_version" {
  description = "Version of the Bedrock Lambda layer"
  value       = aws_lambda_layer_version.bedrock.version
}

output "common_layer_arn" {
  description = "ARN of the common Lambda layer"
  value       = aws_lambda_layer_version.common.arn
}

output "common_layer_version" {
  description = "Version of the common Lambda layer"
  value       = aws_lambda_layer_version.common.version
}

output "all_layer_arns" {
  description = "List of all Lambda layer ARNs"
  value = [
    aws_lambda_layer_version.opensearch.arn,
    aws_lambda_layer_version.bedrock.arn,
    aws_lambda_layer_version.common.arn
  ]
}