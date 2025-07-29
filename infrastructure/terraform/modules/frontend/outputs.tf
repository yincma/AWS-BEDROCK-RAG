output "cloudfront_distribution_id" {
  description = "The ID of the CloudFront distribution"
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.main[0].id : ""
}

output "cloudfront_distribution_arn" {
  description = "The ARN of the CloudFront distribution"
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.main[0].arn : ""
}

output "cloudfront_domain_name" {
  description = "The domain name of the CloudFront distribution"
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.main[0].domain_name : var.frontend_bucket_domain_name
}

output "cloudfront_hosted_zone_id" {
  description = "The CloudFront Route 53 zone ID"
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.main[0].hosted_zone_id : ""
}

output "frontend_url" {
  description = "The URL to access the frontend"
  value       = var.enable_cloudfront ? "https://${aws_cloudfront_distribution.main[0].domain_name}" : "http://${var.frontend_bucket_domain_name}"
}

output "cloudfront_oai_iam_arn" {
  description = "The IAM ARN of the CloudFront Origin Access Identity"
  value       = var.enable_cloudfront ? aws_cloudfront_origin_access_identity.main[0].iam_arn : ""
}