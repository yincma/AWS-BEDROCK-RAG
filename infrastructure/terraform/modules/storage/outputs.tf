output "document_bucket_name" {
  description = "Name of the document storage bucket"
  value       = aws_s3_bucket.documents.id
}

output "document_bucket_arn" {
  description = "ARN of the document storage bucket"
  value       = aws_s3_bucket.documents.arn
}

output "document_bucket_domain_name" {
  description = "Domain name of the document storage bucket"
  value       = aws_s3_bucket.documents.bucket_domain_name
}

output "frontend_bucket_name" {
  description = "Name of the frontend storage bucket"
  value       = aws_s3_bucket.frontend.id
}

output "frontend_bucket_arn" {
  description = "ARN of the frontend storage bucket"
  value       = aws_s3_bucket.frontend.arn
}

output "frontend_bucket_domain_name" {
  description = "Domain name of the frontend storage bucket"
  value       = aws_s3_bucket.frontend.bucket_domain_name
}

output "frontend_bucket_website_endpoint" {
  description = "Website endpoint of the frontend storage bucket"
  value       = aws_s3_bucket_website_configuration.frontend.website_endpoint
}

output "lambda_deployments_bucket_name" {
  description = "Name of the Lambda deployments bucket"
  value       = aws_s3_bucket.lambda_deployments.id
}

output "lambda_deployments_bucket_arn" {
  description = "ARN of the Lambda deployments bucket"
  value       = aws_s3_bucket.lambda_deployments.arn
}