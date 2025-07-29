output "lambda_execution_role_arn" {
  description = "The ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.arn
}

output "lambda_execution_role_name" {
  description = "The name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.name
}

output "lambda_security_group_id" {
  description = "The ID of the Lambda security group"
  value       = aws_security_group.lambda.id
}

output "kms_key_id" {
  description = "The ID of the KMS key"
  value       = aws_kms_key.main.id
}

output "kms_key_arn" {
  description = "The ARN of the KMS key"
  value       = aws_kms_key.main.arn
}

output "kms_key_alias_arn" {
  description = "The ARN of the KMS key alias"
  value       = aws_kms_alias.main.arn
}