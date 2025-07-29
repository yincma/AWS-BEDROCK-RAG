# 主Terraform配置文件（模块化版本）

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

# AWS Provider配置
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# 本地变量
locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    System      = "RAG-Enterprise"
  }
}

# 随机ID（用于资源命名）
resource "random_id" "unique" {
  byte_length = 4
}

# 网络模块
module "networking" {
  source = "./modules/networking"

  project_name         = var.project_name
  environment          = var.environment
  aws_region           = var.aws_region
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
  enable_nat_gateway   = var.enable_nat_gateway
  enable_vpc_endpoints = var.enable_vpc_endpoints
  common_tags          = local.common_tags
}

# 存储模块
module "storage" {
  source = "./modules/storage"

  project_name  = var.project_name
  environment   = var.environment
  common_tags   = local.common_tags
  random_suffix = random_id.unique.hex

  # Lambda函数ARN（用于S3事件通知）
  document_processor_lambda_name = module.document_processor.function_name

  # 文档前缀配置
  document_prefix = var.document_prefix

  # AWS区域
  aws_region = var.aws_region

  # 依赖关系 - 确保Lambda先创建
}

# 安全模块
module "security" {
  source = "./modules/security"

  project_name = var.project_name
  environment  = var.environment
  common_tags  = local.common_tags

  # VPC配置
  vpc_id = module.networking.vpc_id

  # Cognito ARN for IAM policy
  cognito_user_pool_arn = var.enable_cognito ? module.cognito.user_pool_arn : ""
}

# 认证模块 (Cognito)
module "cognito" {
  source = "./modules/cognito"

  project_name = var.project_name
  environment  = var.environment
  common_tags  = local.common_tags

  # 认证配置
  enable_cognito = var.enable_cognito
  cognito_callback_urls = [
    "http://localhost:3000/callback"
  ]
  cognito_logout_urls = [
    "http://localhost:3000/logout"
  ]
  cognito_password_minimum_length = var.cognito_password_minimum_length
  cognito_mfa_configuration       = var.cognito_mfa_configuration
}

# Lambda函数 - 查询处理器（性能优化）
module "query_handler" {
  source = "./modules/lambda"

  function_name = "${var.project_name}-query-handler-${var.environment}"
  handler       = "handler.lambda_handler"
  runtime       = "python3.9"
  memory_size   = var.lambda_memory_configurations["query_handler"].memory_size
  timeout       = var.lambda_memory_configurations["query_handler"].timeout

  # 性能优化配置
  reserved_concurrent_executions    = var.lambda_memory_configurations["query_handler"].reserved_concurrent_executions
  provisioned_concurrent_executions = var.enable_provisioned_concurrency ? var.lambda_memory_configurations["query_handler"].provisioned_concurrent_executions : 0

  role_arn = module.security.lambda_execution_role_arn
  filename = "${path.root}/../../dist/query_handler.zip"

  layers = [module.layers.common_layer_arn, module.layers.bedrock_layer_arn]

  environment_variables = {
    ENVIRONMENT = var.environment
    REGION      = var.aws_region
    # 移除 AWS_REGION，因为它是Lambda保留的环境变量
    KNOWLEDGE_BASE_ID = module.bedrock.knowledge_base_id
    DATA_SOURCE_ID    = module.bedrock.data_source_id
    BEDROCK_MODEL_ID  = var.bedrock_model_id
    S3_BUCKET         = module.storage.document_bucket_name
    LOG_LEVEL         = var.log_level
    # CORS配置
    CORS_ALLOW_ORIGIN  = var.cors_allow_origin
    CORS_ALLOW_METHODS = var.cors_allow_methods
    CORS_ALLOW_HEADERS = var.cors_allow_headers
    # 文档处理配置
    ALLOWED_FILE_EXTENSIONS      = var.allowed_file_extensions
    MAX_FILE_SIZE_MB             = var.max_file_size_mb
    DOCUMENT_PREFIX              = var.document_prefix
    PRESIGNED_URL_EXPIRY_SECONDS = var.presigned_url_expiry_seconds
    # 性能优化环境变量
    ENABLE_LAMBDA_INSIGHTS  = var.enable_lambda_insights
    COLD_START_OPTIMIZATION = var.enable_cold_start_optimization
  }

  # 启用X-Ray追踪
  tracing_mode = var.enable_xray_tracing ? "Active" : "PassThrough"

  tags = local.common_tags
}

# Lambda函数 - 文档处理器
module "document_processor" {
  source = "./modules/lambda"

  function_name = "${var.project_name}-document-processor-${var.environment}"
  handler       = "handler.lambda_handler"
  runtime       = "python3.9"
  memory_size   = var.lambda_memory_size
  timeout       = var.lambda_timeout

  role_arn = module.security.lambda_execution_role_arn
  filename = "${path.root}/../../dist/document_processor.zip"

  layers = [module.layers.common_layer_arn]

  environment_variables = {
    ENVIRONMENT = var.environment
    REGION      = var.aws_region
    # 移除 AWS_REGION，因为它是Lambda保留的环境变量
    S3_BUCKET         = module.storage.document_bucket_name
    KNOWLEDGE_BASE_ID = module.bedrock.knowledge_base_id
    DATA_SOURCE_ID    = module.bedrock.data_source_id
    LOG_LEVEL         = var.log_level
    # CORS配置
    CORS_ALLOW_ORIGIN  = var.cors_allow_origin
    CORS_ALLOW_METHODS = var.cors_allow_methods
    CORS_ALLOW_HEADERS = var.cors_allow_headers
    # 文档处理配置
    ALLOWED_FILE_EXTENSIONS      = var.allowed_file_extensions
    MAX_FILE_SIZE_MB             = var.max_file_size_mb
    DOCUMENT_PREFIX              = var.document_prefix
    PRESIGNED_URL_EXPIRY_SECONDS = var.presigned_url_expiry_seconds
    # Lambda配置
    LAMBDA_MEMORY_SIZE = var.lambda_memory_size
    LAMBDA_TIMEOUT     = var.lambda_timeout
  }

  tags = local.common_tags
}

# Commented out - using Cognito authorizer instead
# # Lambda函数 - 认证器
# module "authorizer" {
#   source = "./modules/lambda"
#   
#   function_name = "${var.project_name}-authorizer-${var.environment}"
#   handler       = "authorizer.lambda_handler"
#   runtime       = "python3.9"
#   memory_size   = 256
#   timeout       = 30
#   
#   role_arn = module.security.lambda_execution_role_arn
#   filename = "${path.root}/../../dist/authorizer.zip"
# 
#   layers = [module.layers.common_layer_arn]
# 
#   environment_variables = {
#     ENVIRONMENT    = var.environment
#     USER_POOL_ID   = module.cognito.user_pool_id
#     APP_CLIENT_ID  = module.cognito.user_pool_client_id
#     REGION         = var.aws_region
#     LOG_LEVEL      = var.log_level
#   }
#   
#   tags = local.common_tags
# }

# API Gateway模块
module "api_gateway" {
  source = "./modules/compute/api_gateway"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region
  common_tags  = local.common_tags

  # Lambda函数名称映射
  lambda_function_names = {
    query_handler      = module.query_handler.function_name
    document_processor = module.document_processor.function_name
    # authorizer         = module.authorizer.function_name  # Using Cognito authorizer
    index_creator = module.index_creator.function_name
  }

  # Lambda函数ARN映射
  lambda_function_arns = {
    query_handler      = module.query_handler.function_arn
    document_processor = module.document_processor.function_arn
    # authorizer         = module.authorizer.function_arn  # Using Cognito authorizer
    index_creator = module.index_creator.function_arn
  }

  # Lambda函数调用ARN映射
  lambda_function_invoke_arns = {
    query_handler      = module.query_handler.invoke_arn
    document_processor = module.document_processor.invoke_arn
    # authorizer         = module.authorizer.invoke_arn  # Using Cognito authorizer
    index_creator = module.index_creator.invoke_arn
  }

  # Lambda函数源代码哈希映射
  lambda_source_code_hashes = {
    query_handler      = module.query_handler.source_code_hash
    document_processor = module.document_processor.source_code_hash
    # authorizer         = module.authorizer.source_code_hash  # Using Cognito authorizer
    index_creator = module.index_creator.source_code_hash
  }

  # 认证配置
  cognito_user_pool_arn = module.cognito.user_pool_arn

  # CORS配置
  enable_cors          = true
  cors_allowed_origins = var.allowed_origins
}

# Bedrock Knowledge Base模块
module "bedrock" {
  source = "./modules/bedrock"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region
  common_tags  = local.common_tags

  # S3配置
  document_bucket_name = module.storage.document_bucket_name
  document_bucket_arn  = module.storage.document_bucket_arn

  # 模型配置
  embedding_model_id = var.bedrock_embedding_model_id

  # 启用 Bedrock Knowledge Base
  enable_bedrock_knowledge_base = true
}

# Lambda层模块
module "layers" {
  source = "./modules/compute/layers"

  project_name = var.project_name
  environment  = var.environment
  common_tags  = local.common_tags

  # 层源码目录（可选）
  layer_source_dir = "${path.root}/../../dist"
}

# 前端模块
module "frontend" {
  source = "./modules/frontend"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region
  common_tags  = local.common_tags

  # S3存储桶
  frontend_bucket_name        = module.storage.frontend_bucket_name
  frontend_bucket_arn         = module.storage.frontend_bucket_arn
  frontend_bucket_domain_name = module.storage.frontend_bucket_domain_name

  # API配置
  api_gateway_url = module.api_gateway.api_endpoint

  # 认证配置
  cognito_user_pool_id        = module.cognito.user_pool_id
  cognito_user_pool_client_id = module.cognito.user_pool_client_id
}

# 监控模块
module "monitoring" {
  source = "./modules/monitoring"

  project_name = var.project_name
  environment  = var.environment
  common_tags  = local.common_tags

  # 告警配置
  alarm_email = var.alarm_email

  # API Gateway配置
  api_gateway_name  = "${var.project_name}-api-${var.environment}"
  api_gateway_stage = var.environment

  # Lambda函数配置
  lambda_functions = [
    module.query_handler.function_name,
    module.document_processor.function_name,
    # module.authorizer.function_name,  # Using Cognito authorizer
    module.index_creator.function_name
  ]

  # 成本告警配置
  cost_alert_threshold = var.cost_alert_threshold

  # X-Ray配置
  enable_xray_tracing = var.enable_xray_tracing

  # Synthetics配置
  enable_synthetics = var.enable_synthetics
  api_endpoint      = module.api_gateway.api_endpoint

  # 确保Lambda函数先创建
  depends_on = [
    module.query_handler,
    module.document_processor,
    module.index_creator,
    # module.authorizer,  # Using Cognito authorizer
  ]
}

# Lambda函数 - 索引创建器（特殊用途）
module "index_creator" {
  source = "./modules/lambda"

  function_name = "${var.project_name}-index-creator-${var.environment}"
  handler       = "index.lambda_handler"
  runtime       = "python3.9"
  memory_size   = 512
  timeout       = 300

  role_arn = module.security.lambda_execution_role_arn
  filename = "${path.root}/../../dist/index_creator.zip"

  environment_variables = {
    ENVIRONMENT = var.environment
    REGION      = var.aws_region
    LOG_LEVEL   = var.log_level
  }

  tags = local.common_tags
}

# Import existing OpenSearch Serverless Security Policy (encryption)
# NOTE: Commented out - These resources need to be created first before importing
# import {
#   to = module.bedrock.aws_opensearchserverless_security_policy.knowledge_base[0]
#   id = "enterpriseragkbsecuritydev/encryption"
# }

# Import existing OpenSearch Serverless Security Policy (network)
# import {
#   to = module.bedrock.aws_opensearchserverless_security_policy.knowledge_base_network[0]
#   id = "enterpriseragkbnetworkdev/network"
# }

# Import existing OpenSearch Serverless Security Policies
# Uncomment and update these imports if the resources already exist
# import {
#   to = module.bedrock.aws_opensearchserverless_security_policy.knowledge_base[0]
#   id = "${replace("${var.project_name}-kb-security-${var.environment}", "-", "")}/encryption"
# }

# import {
#   to = module.bedrock.aws_opensearchserverless_security_policy.knowledge_base_network[0]
#   id = "${replace("${var.project_name}-kb-network-${var.environment}", "-", "")}/network"
# }

# Import existing OpenSearch Serverless Access Policy
# import {
#   to = module.bedrock.aws_opensearchserverless_access_policy.knowledge_base[0]
#   id = "${replace("${var.project_name}-kb-access-${var.environment}", "-", "")}/data"
# }

# Import existing KMS alias
# import {
#   to = module.security.aws_kms_alias.main
#   id = "alias/enterprise-rag-dev"
# }

# Import existing OpenSearch Serverless Collection
# import {
#   to = module.bedrock.aws_opensearchserverless_collection.knowledge_base[0]
#   id = "enterpriseragkbcollectiondev"
# }

# Import existing CloudWatch Log Groups
# import {
#   to = module.monitoring.aws_cloudwatch_log_group.lambda_logs["enterprise-rag-authorizer-dev"]
#   id = "/aws/lambda/enterprise-rag-authorizer-dev"
# }

# import {
#   to = module.monitoring.aws_cloudwatch_log_group.lambda_logs["enterprise-rag-query-handler-dev"]
#   id = "/aws/lambda/enterprise-rag-query-handler-dev"
# }

# import {
#   to = module.monitoring.aws_cloudwatch_log_group.lambda_logs["enterprise-rag-index-creator-dev"]
#   id = "/aws/lambda/enterprise-rag-index-creator-dev"
# }

# import {
#   to = module.monitoring.aws_cloudwatch_log_group.lambda_logs["enterprise-rag-document-processor-dev"]
#   id = "/aws/lambda/enterprise-rag-document-processor-dev"
# }

# Import existing X-Ray Sampling Rule
# import {
#   to = module.monitoring.aws_xray_sampling_rule.main[0]
#   id = "enterprise-rag-sampling-dev"
# }