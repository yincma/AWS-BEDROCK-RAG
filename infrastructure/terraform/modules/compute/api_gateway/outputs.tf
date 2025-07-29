output "api_id" {
  description = "The ID of the REST API"
  value       = aws_api_gateway_rest_api.main.id
}

output "api_arn" {
  description = "The ARN of the REST API"
  value       = aws_api_gateway_rest_api.main.arn
}

output "api_execution_arn" {
  description = "The execution ARN of the REST API"
  value       = aws_api_gateway_rest_api.main.execution_arn
}

output "api_endpoint" {
  description = "The endpoint URL of the REST API"
  value       = aws_api_gateway_stage.main.invoke_url
}

output "api_stage_name" {
  description = "The name of the API stage"
  value       = aws_api_gateway_stage.main.stage_name
}

output "api_root_resource_id" {
  description = "The resource ID of the REST API's root"
  value       = aws_api_gateway_rest_api.main.root_resource_id
}

output "authorizer_id" {
  description = "The ID of the API Gateway authorizer"
  value       = aws_api_gateway_authorizer.cognito.id
}

# Performance optimization outputs
output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.api_cdn[0].id : null
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.api_cdn[0].domain_name : null
}

output "api_gateway_cache_status" {
  description = "API Gateway cache status"
  value       = var.enable_caching ? "Enabled" : "Disabled"
}

output "performance_dashboard_url" {
  description = "CloudWatch dashboard URL for API performance"
  value       = var.enable_caching || var.enable_cloudfront ? "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${var.project_name}-api-performance" : null
}

output "usage_plan_id" {
  description = "API Gateway usage plan ID"
  value       = aws_api_gateway_usage_plan.main.id
}

output "cached_stage_name" {
  description = "API Gateway cached stage name"
  value       = var.enable_caching ? aws_api_gateway_stage.optimized[0].stage_name : null
}