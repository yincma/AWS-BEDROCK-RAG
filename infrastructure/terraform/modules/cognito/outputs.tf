output "user_pool_id" {
  description = "The ID of the Cognito User Pool"
  value       = var.enable_cognito ? aws_cognito_user_pool.main[0].id : ""
}

output "user_pool_arn" {
  description = "The ARN of the Cognito User Pool"
  value       = var.enable_cognito ? aws_cognito_user_pool.main[0].arn : ""
}

output "user_pool_endpoint" {
  description = "The endpoint of the Cognito User Pool"
  value       = var.enable_cognito ? aws_cognito_user_pool.main[0].endpoint : ""
}

output "user_pool_client_id" {
  description = "The ID of the Cognito User Pool Client"
  value       = var.enable_cognito ? aws_cognito_user_pool_client.main[0].id : ""
}

output "user_pool_domain" {
  description = "The Cognito User Pool domain"
  value       = var.enable_cognito ? aws_cognito_user_pool_domain.main[0].domain : ""
}