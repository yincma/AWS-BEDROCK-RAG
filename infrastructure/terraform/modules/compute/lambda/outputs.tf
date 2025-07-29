# Lambda模块输出

output "function_arn" {
  description = "Lambda函数ARN"
  value       = aws_lambda_function.function.arn
}

output "function_name" {
  description = "Lambda函数名称"
  value       = aws_lambda_function.function.function_name
}

output "invoke_arn" {
  description = "Lambda函数调用ARN"
  value       = aws_lambda_function.function.invoke_arn
}

output "version" {
  description = "Lambda函数版本"
  value       = aws_lambda_function.function.version
}

output "alias_arn" {
  description = "Lambda别名ARN"
  value       = try(aws_lambda_alias.live[0].arn, null)
}

output "function_url" {
  description = "Lambda函数URL"
  value       = try(aws_lambda_function_url.function_url[0].function_url, null)
}

output "dlq_arn" {
  description = "死信队列ARN"
  value       = try(aws_sqs_queue.dlq[0].arn, null)
}

output "log_group_name" {
  description = "CloudWatch日志组名称"
  value       = "/aws/lambda/${var.function_name}"
}

output "error_alarm_arn" {
  description = "错误告警ARN"
  value       = try(aws_cloudwatch_metric_alarm.error_rate[0].arn, null)
}

output "duration_alarm_arn" {
  description = "执行时间告警ARN"
  value       = try(aws_cloudwatch_metric_alarm.duration[0].arn, null)
}

output "concurrent_executions_alarm_arn" {
  description = "并发执行告警ARN"
  value       = try(aws_cloudwatch_metric_alarm.concurrent_executions[0].arn, null)
}

output "source_code_hash" {
  description = "Lambda函数源代码哈希值"
  value       = aws_lambda_function.function.source_code_hash
}