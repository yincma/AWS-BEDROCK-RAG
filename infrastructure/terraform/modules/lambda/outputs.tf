# Lambda 函数输出
output "function_arn" {
  description = "Lambda 函数 ARN"
  value       = aws_lambda_function.this.arn
}

output "function_name" {
  description = "Lambda 函数名称"
  value       = aws_lambda_function.this.function_name
}

output "function_qualified_arn" {
  description = "Lambda 函数限定 ARN"
  value       = aws_lambda_function.this.qualified_arn
}

output "function_version" {
  description = "Lambda 函数版本"
  value       = aws_lambda_function.this.version
}

output "function_last_modified" {
  description = "Lambda 函数最后修改时间"
  value       = aws_lambda_function.this.last_modified
}

output "function_source_code_size" {
  description = "Lambda 函数源代码大小"
  value       = aws_lambda_function.this.source_code_size
}

output "function_runtime" {
  description = "Lambda 函数运行时"
  value       = aws_lambda_function.this.runtime
}

# 日志组输出
output "log_group_name" {
  description = "CloudWatch 日志组名称"
  value       = aws_cloudwatch_log_group.this.name
}

output "log_group_arn" {
  description = "CloudWatch 日志组 ARN"
  value       = aws_cloudwatch_log_group.this.arn
}

# Lambda 层输出
output "layer_arns" {
  description = "Lambda 层 ARN 映射"
  value       = { for k, v in aws_lambda_layer_version.this : k => v.arn }
}

output "layer_versions" {
  description = "Lambda 层版本映射"
  value       = { for k, v in aws_lambda_layer_version.this : k => v.version }
}

# 函数 URL 输出
output "function_url" {
  description = "Lambda 函数 URL"
  value       = var.create_function_url ? aws_lambda_function_url.this[0].function_url : null
}

output "function_url_config" {
  description = "Lambda 函数 URL 配置"
  value = var.create_function_url ? {
    url                = aws_lambda_function_url.this[0].function_url
    authorization_type = aws_lambda_function_url.this[0].authorization_type
    cors               = aws_lambda_function_url.this[0].cors
  } : null
}

# 别名输出
output "alias_arn" {
  description = "Lambda 别名 ARN"
  value       = var.create_alias ? aws_lambda_alias.live[0].arn : null
}

output "alias_name" {
  description = "Lambda 别名名称"
  value       = var.create_alias ? aws_lambda_alias.live[0].name : null
}

output "alias_invoke_arn" {
  description = "Lambda 别名调用 ARN"
  value       = var.create_alias ? aws_lambda_alias.live[0].invoke_arn : null
}

# 预留并发输出
output "provisioned_concurrent_executions" {
  description = "预配置的并发执行数"
  value       = var.provisioned_concurrent_executions > 0 && var.create_alias ? aws_lambda_provisioned_concurrency_config.this[0].provisioned_concurrent_executions : null
}

# 事件源映射输出
output "event_source_mapping_ids" {
  description = "事件源映射 ID 映射"
  value       = { for k, v in aws_lambda_event_source_mapping.this : k => v.id }
}

output "event_source_mapping_arns" {
  description = "事件源映射 ARN 映射"
  value       = { for k, v in aws_lambda_event_source_mapping.this : k => v.arn }
}

output "event_source_mapping_states" {
  description = "事件源映射状态映射"
  value       = { for k, v in aws_lambda_event_source_mapping.this : k => v.state }
}

# 异步调用配置输出
output "async_invoke_config" {
  description = "异步调用配置"
  value = var.async_invoke_config != null ? {
    maximum_event_age_in_seconds = aws_lambda_function_event_invoke_config.this[0].maximum_event_age_in_seconds
    maximum_retry_attempts       = aws_lambda_function_event_invoke_config.this[0].maximum_retry_attempts
    destination_config           = aws_lambda_function_event_invoke_config.this[0].destination_config
  } : null
}

# 执行角色
output "execution_role_id" {
  description = "Lambda 执行角色 ID"
  value       = aws_lambda_function.this.role
}

# 调用 ARN（用于 API Gateway 等服务）
output "invoke_arn" {
  description = "Lambda 函数调用 ARN"
  value       = aws_lambda_function.this.invoke_arn
}

# 源代码哈希输出
output "source_code_hash" {
  description = "Lambda 函数源代码哈希"
  value       = aws_lambda_function.this.source_code_hash
}