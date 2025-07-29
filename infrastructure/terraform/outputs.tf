# 系统二：AWS Bedrock企业级RAG系统
# 模块化 Terraform 输出

# 主要访问端点
output "endpoints" {
  description = "系统访问端点"
  value = {
    frontend_url  = module.frontend.frontend_url
    api_base_url  = module.api_gateway.api_endpoint
    query_api     = "${module.api_gateway.api_endpoint}/query"
    documents_api = "${module.api_gateway.api_endpoint}/documents"
    index_api     = "${module.api_gateway.api_endpoint}/index"
  }
}

# 关键资源信息
output "key_resources" {
  description = "关键资源标识"
  value = {
    environment             = var.environment
    region                  = var.aws_region
    document_bucket         = module.storage.document_bucket_name
    frontend_bucket         = module.storage.frontend_bucket_name
    knowledge_base_id       = module.bedrock.knowledge_base_id
    data_source_id          = module.bedrock.data_source_id
    api_gateway_id          = module.api_gateway.api_id
    cloudfront_distribution = module.frontend.cloudfront_distribution_id
  }
}

# 认证信息
output "authentication" {
  description = "认证相关信息"
  value = {
    user_pool_id        = module.cognito.user_pool_id
    user_pool_client_id = module.cognito.user_pool_client_id
    user_pool_domain    = module.cognito.user_pool_domain
    user_pool_endpoint  = module.cognito.user_pool_endpoint
  }
}

# 单独的认证输出（为了兼容性）
output "user_pool_id" {
  description = "Cognito User Pool ID"
  value       = module.cognito.user_pool_id
}

output "user_pool_client_id" {
  description = "Cognito User Pool Client ID"
  value       = module.cognito.user_pool_client_id
}

# Lambda 函数信息
output "lambda_functions" {
  description = "Lambda 函数信息"
  value = {
    query_handler      = module.query_handler.function_name
    document_processor = module.document_processor.function_name
    # authorizer         = module.authorizer.function_name  # Using Cognito authorizer
    index_creator = module.index_creator.function_name
  }
}

# Lambda 层信息
output "lambda_layers" {
  description = "Lambda 层 ARN"
  value = {
    opensearch_layer = module.layers.opensearch_layer_arn
    bedrock_layer    = module.layers.bedrock_layer_arn
    common_layer     = module.layers.common_layer_arn
  }
}

# 网络信息
output "networking" {
  description = "网络资源信息"
  value = {
    vpc_id                = module.networking.vpc_id
    private_subnet_ids    = module.networking.private_subnet_ids
    public_subnet_ids     = module.networking.public_subnet_ids
    lambda_security_group = module.networking.lambda_security_group_id
  }
}

# 监控信息
output "monitoring" {
  description = "监控和日志"
  value = {
    cloudwatch_dashboard = module.monitoring.dashboard_url
    alerts_topic_arn     = module.monitoring.alerts_topic_arn
    synthetics_canary    = module.monitoring.synthetics_canary_name
  }
  sensitive = true
}

# 快速开始
output "quick_start" {
  description = "快速开始指南"
  value = {
    step1_upload_document = "aws s3 cp document.pdf s3://${module.storage.document_bucket_name}/"
    step2_sync_knowledge  = module.bedrock.knowledge_base_id != "" ? "aws bedrock-agent start-ingestion-job --knowledge-base-id ${module.bedrock.knowledge_base_id} --data-source-id ${module.bedrock.data_source_id}" : "Bedrock Knowledge Base not enabled"
    step3_test_query      = "curl -X POST ${module.api_gateway.api_endpoint}/query -H 'Content-Type: application/json' -H 'Authorization: Bearer <token>' -d '{\"question\":\"测试问题\"}'"
  }
}

# 开发环境变量
output "env_variables" {
  description = "开发环境变量"
  value = {
    AWS_REGION          = var.aws_region
    ENVIRONMENT         = var.environment
    S3_BUCKET           = module.storage.document_bucket_name
    KNOWLEDGE_BASE_ID   = module.bedrock.knowledge_base_id
    BEDROCK_MODEL_ID    = var.bedrock_model_id
    API_GATEWAY_URL     = module.api_gateway.api_endpoint
    USER_POOL_ID        = module.cognito.user_pool_id
    USER_POOL_CLIENT_ID = module.cognito.user_pool_client_id
  }
}

# 部署状态
output "deployment_status" {
  description = "部署状态信息"
  value = {
    deployment_time   = timestamp()
    project_name      = var.project_name
    environment       = var.environment
    bedrock_enabled   = var.enable_bedrock_knowledge_base ? "✅ Enabled" : "❌ Disabled"
    cognito_enabled   = var.enable_cognito ? "✅ Enabled" : "❌ Disabled"
    cloudfront_status = module.frontend.cloudfront_distribution_id != "" ? "✅ Active" : "❌ Not configured"
  }
}

# 直接输出（向后兼容脚本）
output "api_gateway_id" {
  description = "API Gateway ID"
  value       = module.api_gateway.api_id
}

output "api_gateway_url" {
  description = "API Gateway URL"
  value       = module.api_gateway.api_endpoint
}

output "aws_region" {
  description = "AWS Region"
  value       = var.aws_region
}

output "frontend_bucket" {
  description = "Frontend S3 bucket name"
  value       = module.storage.frontend_bucket_name
}

output "frontend_bucket_name" {
  description = "Frontend S3 bucket name (alias)"
  value       = module.storage.frontend_bucket_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = module.frontend.cloudfront_distribution_id
}

output "cloudfront_url" {
  description = "CloudFront URL"
  value       = module.frontend.frontend_url
}

output "frontend_url" {
  description = "Frontend URL (alias)"
  value       = module.frontend.frontend_url
}

output "document_bucket_name" {
  description = "Document S3 bucket name"
  value       = module.storage.document_bucket_name
}

output "document_bucket_arn" {
  description = "Document S3 bucket ARN"
  value       = module.storage.document_bucket_arn
}

output "frontend_bucket_arn" {
  description = "Frontend S3 bucket ARN"
  value       = module.storage.frontend_bucket_arn
}

output "frontend_bucket_domain_name" {
  description = "Frontend S3 bucket domain name"
  value       = module.storage.frontend_bucket_domain_name
}

output "performance_dashboard_url" {
  description = "Performance dashboard URL"
  value       = try(module.monitoring.dashboard_url, "")
}

output "cloudfront_domain_name" {
  description = "CloudFront domain name"
  value       = try(module.frontend.cloudfront_domain_name, "")
}