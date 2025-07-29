# 完整标签使用示例

module "tags" {
  source = "../../"

  # 基本信息
  project_name    = "rag-system"
  environment     = "prod"
  owner           = "platform-team"
  cost_center     = "Engineering"
  project_version = "2.1.0"

  # 启用所有标签类别
  enable_compliance_tags = true
  enable_technical_tags  = true
  enable_automation_tags = true

  # 合规性配置
  data_classification  = "Confidential"
  compliance_framework = "SOC2"
  backup_required      = true
  retention_period     = "2555" # 7年

  # 技术配置
  stack_name         = "serverless"
  component_name     = "api-layer"
  deployment_method  = "terraform-cicd"
  monitoring_enabled = true

  # 自动化配置
  auto_scaling_enabled  = true
  auto_shutdown_enabled = false
  auto_backup_enabled   = true
  maintenance_window    = "sun:02:00-sun:04:00"

  # 额外标签
  additional_tags = {
    Team             = "Platform"
    Application      = "RAG"
    BusinessUnit     = "AI-ML"
    SupportLevel     = "Premium"
    ChangeControl    = "Required"
    DisasterRecovery = "Enabled"
  }
}

# 使用不同的标签集合
resource "aws_lambda_function" "example" {
  function_name = "example-function"
  role          = aws_iam_role.lambda.arn
  handler       = "index.handler"
  runtime       = "python3.9"

  # 使用所有标签
  tags = module.tags.common_tags
}

resource "aws_s3_bucket" "logs" {
  bucket = "example-logs-bucket"

  # 仅使用合规性相关的标签
  tags = merge(
    module.tags.default_tags,
    module.tags.compliance_tags
  )
}

# 输出不同的标签集合
output "all_tags" {
  value = module.tags.common_tags
}

output "compliance_only" {
  value = module.tags.compliance_tags
}

output "tags_count" {
  value = length(module.tags.common_tags)
}