# 基本标签使用示例

module "tags" {
  source = "../../"

  # 必需参数
  project_name = "rag-system"
  environment  = "dev"
  owner        = "devops-team"

  # 可选参数
  cost_center     = "Engineering"
  project_version = "1.0.0"

  # 仅启用默认标签
  enable_compliance_tags = false
  enable_technical_tags  = false
  enable_automation_tags = false

  # 添加自定义标签
  additional_tags = {
    Team        = "Platform"
    Application = "RAG"
  }
}

# 使用标签创建 S3 桶
resource "aws_s3_bucket" "example" {
  bucket = "example-bucket-with-tags"

  tags = module.tags.common_tags
}

# 输出标签
output "all_tags" {
  value = module.tags.common_tags
}