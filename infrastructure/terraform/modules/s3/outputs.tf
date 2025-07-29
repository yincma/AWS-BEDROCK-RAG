# 桶基本信息
output "bucket_id" {
  description = "S3 桶 ID"
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "S3 桶 ARN"
  value       = aws_s3_bucket.this.arn
}

output "bucket_domain_name" {
  description = "S3 桶域名"
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "S3 桶区域域名"
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "bucket_region" {
  description = "S3 桶所在区域"
  value       = aws_s3_bucket.this.region
}

# 网站托管相关
output "website_endpoint" {
  description = "S3 静态网站端点"
  value       = var.enable_website_hosting ? aws_s3_bucket_website_configuration.this[0].website_endpoint : null
}

output "website_domain" {
  description = "S3 静态网站域名"
  value       = var.enable_website_hosting ? aws_s3_bucket_website_configuration.this[0].website_domain : null
}

# 加速端点
output "accelerate_endpoint" {
  description = "S3 加速端点"
  value       = var.enable_acceleration ? "${aws_s3_bucket.this.id}.s3-accelerate.amazonaws.com" : null
}

# 版本控制状态
output "versioning_enabled" {
  description = "版本控制是否启用"
  value       = var.enable_versioning
}

# 加密信息
output "encryption_algorithm" {
  description = "使用的加密算法"
  value       = var.encryption_algorithm
}

output "kms_key_id" {
  description = "KMS 密钥 ID（如果使用）"
  value       = var.kms_key_id
}