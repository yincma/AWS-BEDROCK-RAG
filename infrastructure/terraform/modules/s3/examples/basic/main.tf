# 基本 S3 桶配置示例

module "basic_bucket" {
  source = "../../"

  bucket_name = "my-basic-bucket-example"
  bucket_type = "general"

  # 基本配置
  enable_versioning   = true
  block_public_access = true

  # 使用默认 AES256 加密
  encryption_algorithm = "AES256"

  # 简单的生命周期规则
  lifecycle_rules = [
    {
      id              = "delete-old-objects"
      enabled         = true
      expiration_days = 90
    }
  ]

  tags = {
    Environment = "dev"
    Purpose     = "example"
  }
}

# 输出
output "bucket_id" {
  value = module.basic_bucket.bucket_id
}

output "bucket_arn" {
  value = module.basic_bucket.bucket_arn
}