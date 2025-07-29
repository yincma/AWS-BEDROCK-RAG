# Lambda 角色输出
output "lambda_role_arn" {
  description = "Lambda 执行角色 ARN"
  value       = var.create_lambda_role ? aws_iam_role.lambda_execution[0].arn : null
}

output "lambda_role_name" {
  description = "Lambda 执行角色名称"
  value       = var.create_lambda_role ? aws_iam_role.lambda_execution[0].name : null
}

output "lambda_role_id" {
  description = "Lambda 执行角色 ID"
  value       = var.create_lambda_role ? aws_iam_role.lambda_execution[0].id : null
}

# API Gateway 角色输出
output "api_gateway_role_arn" {
  description = "API Gateway 角色 ARN"
  value       = var.create_api_gateway_role ? aws_iam_role.api_gateway[0].arn : null
}

output "api_gateway_role_name" {
  description = "API Gateway 角色名称"
  value       = var.create_api_gateway_role ? aws_iam_role.api_gateway[0].name : null
}

# S3 复制角色输出
output "s3_replication_role_arn" {
  description = "S3 复制角色 ARN"
  value       = var.create_s3_replication_role ? aws_iam_role.s3_replication[0].arn : null
}

# 服务账号角色输出
output "service_account_role_arn" {
  description = "服务账号角色 ARN"
  value       = var.create_service_account_role ? aws_iam_role.service_account[0].arn : null
}