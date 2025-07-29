# Main Terraform configuration file (modular version)

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

# AWS Provider configuration
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# Local variables
locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    System      = "RAG-Enterprise"
  }
}

# Random ID (for resource naming)
resource "random_id" "unique" {
  byte_length = 4
}

# Networking module
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

# Storage module
module "storage" {
  source = "./modules/storage"

  project_name  = var.project_name
  environment   = var.environment
  common_tags   = local.common_tags
  random_suffix = random_id.unique.hex

  # Lambda function ARN (for S3 event notifications)
  document_processor_lambda_name = module.document_processor.function_name

  # Document prefix configuration
  document_prefix = var.document_prefix

  # AWS region
  aws_region = var.aws_region

  # Dependencies - ensure Lambda is created first
}

# Security module
module "security" {
  source = "./modules/security"

  project_name = var.project_name
  environment  = var.environment
  common_tags  = local.common_tags

  # VPC configuration
  vpc_id = module.networking.vpc_id

  # Cognito ARN for IAM policy
  cognito_user_pool_arn = var.enable_cognito ? module.cognito.user_pool_arn : ""
}

# Authentication module (Cognito)
module "cognito" {
  source = "./modules/cognito"

  project_name = var.project_name
  environment  = var.environment
  common_tags  = local.common_tags

  # Authentication configuration
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

# Lambda function - Query handler (performance optimized)
module "query_handler" {
  source = "./modules/lambda"

  function_name = "${var.project_name}-query-handler-${var.environment}"
  handler       = "handler.lambda_handler"
  runtime       = "python3.9"
  memory_size   = var.lambda_memory_configurations["query_handler"].memory_size
  timeout       = var.lambda_memory_configurations["query_handler"].timeout

  # Performance optimization configuration
  reserved_concurrent_executions    = var.lambda_memory_configurations["query_handler"].reserved_concurrent_executions
  provisioned_concurrent_executions = var.enable_provisioned_concurrency ? var.lambda_memory_configurations["query_handler"].provisioned_concurrent_executions : 0

  role_arn = module.security.lambda_execution_role_arn
  filename = "${path.root}/../../dist/query_handler.zip"

  layers = [module.layers.common_layer_arn, module.layers.bedrock_layer_arn]

  environment_variables = {
    ENVIRONMENT = var.environment
    REGION      = var.aws_region
    # Remove AWS_REGION as it's a reserved Lambda environment variable
    KNOWLEDGE_BASE_ID = module.bedrock.knowledge_base_id
    DATA_SOURCE_ID    = module.bedrock.data_source_id
    BEDROCK_MODEL_ID  = var.bedrock_model_id
    S3_BUCKET         = module.storage.document_bucket_name
    LOG_LEVEL         = var.log_level
    # CORS configuration
    CORS_ALLOW_ORIGIN  = var.cors_allow_origin
    CORS_ALLOW_METHODS = var.cors_allow_methods
    CORS_ALLOW_HEADERS = var.cors_allow_headers
    # Document processing configuration
    ALLOWED_FILE_EXTENSIONS      = var.allowed_file_extensions
    MAX_FILE_SIZE_MB             = var.max_file_size_mb
    DOCUMENT_PREFIX              = var.document_prefix
    PRESIGNED_URL_EXPIRY_SECONDS = var.presigned_url_expiry_seconds
    # Performance optimization environment variables
    ENABLE_LAMBDA_INSIGHTS  = var.enable_lambda_insights
    COLD_START_OPTIMIZATION = var.enable_cold_start_optimization
  }

  # Enable X-Ray tracing
  tracing_mode = var.enable_xray_tracing ? "Active" : "PassThrough"

  tags = local.common_tags
}

# Lambda function - Document processor
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
    # Remove AWS_REGION as it's a reserved Lambda environment variable
    S3_BUCKET         = module.storage.document_bucket_name
    KNOWLEDGE_BASE_ID = module.bedrock.knowledge_base_id
    DATA_SOURCE_ID    = module.bedrock.data_source_id
    LOG_LEVEL         = var.log_level
    # CORS configuration
    CORS_ALLOW_ORIGIN  = var.cors_allow_origin
    CORS_ALLOW_METHODS = var.cors_allow_methods
    CORS_ALLOW_HEADERS = var.cors_allow_headers
    # Document processing configuration
    ALLOWED_FILE_EXTENSIONS      = var.allowed_file_extensions
    MAX_FILE_SIZE_MB             = var.max_file_size_mb
    DOCUMENT_PREFIX              = var.document_prefix
    PRESIGNED_URL_EXPIRY_SECONDS = var.presigned_url_expiry_seconds
    # Lambda configuration
    LAMBDA_MEMORY_SIZE = var.lambda_memory_size
    LAMBDA_TIMEOUT     = var.lambda_timeout
  }

  tags = local.common_tags
}

# Commented out - using Cognito authorizer instead
# # Lambda function - Authorizer
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

# API Gateway module
module "api_gateway" {
  source = "./modules/compute/api_gateway"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region
  common_tags  = local.common_tags

  # Lambda function name mapping
  lambda_function_names = {
    query_handler      = module.query_handler.function_name
    document_processor = module.document_processor.function_name
    # authorizer         = module.authorizer.function_name  # Using Cognito authorizer
    index_creator = module.index_creator.function_name
  }

  # Lambda function ARN mapping
  lambda_function_arns = {
    query_handler      = module.query_handler.function_arn
    document_processor = module.document_processor.function_arn
    # authorizer         = module.authorizer.function_arn  # Using Cognito authorizer
    index_creator = module.index_creator.function_arn
  }

  # Lambda function invoke ARN mapping
  lambda_function_invoke_arns = {
    query_handler      = module.query_handler.invoke_arn
    document_processor = module.document_processor.invoke_arn
    # authorizer         = module.authorizer.invoke_arn  # Using Cognito authorizer
    index_creator = module.index_creator.invoke_arn
  }

  # Lambda function source code hash mapping
  lambda_source_code_hashes = {
    query_handler      = module.query_handler.source_code_hash
    document_processor = module.document_processor.source_code_hash
    # authorizer         = module.authorizer.source_code_hash  # Using Cognito authorizer
    index_creator = module.index_creator.source_code_hash
  }

  # Authentication configuration
  cognito_user_pool_arn = module.cognito.user_pool_arn

  # CORS configuration
  enable_cors          = true
  cors_allowed_origins = var.allowed_origins
}

# Bedrock Knowledge Base module
module "bedrock" {
  source = "./modules/bedrock"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region
  common_tags  = local.common_tags

  # S3 configuration
  document_bucket_name = module.storage.document_bucket_name
  document_bucket_arn  = module.storage.document_bucket_arn

  # Model configuration
  embedding_model_id = var.bedrock_embedding_model_id

  # Enable Bedrock Knowledge Base
  enable_bedrock_knowledge_base = true
}

# Lambda layers module
module "layers" {
  source = "./modules/compute/layers"

  project_name = var.project_name
  environment  = var.environment
  common_tags  = local.common_tags

  # Layer source directory (optional)
  layer_source_dir = "${path.root}/../../dist"
}

# Frontend module
module "frontend" {
  source = "./modules/frontend"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region
  common_tags  = local.common_tags

  # S3 bucket
  frontend_bucket_name        = module.storage.frontend_bucket_name
  frontend_bucket_arn         = module.storage.frontend_bucket_arn
  frontend_bucket_domain_name = module.storage.frontend_bucket_domain_name

  # API configuration
  api_gateway_url = module.api_gateway.api_endpoint

  # Authentication configuration
  cognito_user_pool_id        = module.cognito.user_pool_id
  cognito_user_pool_client_id = module.cognito.user_pool_client_id
}

# Monitoring module
module "monitoring" {
  source = "./modules/monitoring"

  project_name = var.project_name
  environment  = var.environment
  common_tags  = local.common_tags

  # Alarm configuration
  alarm_email = var.alarm_email

  # API Gateway configuration
  api_gateway_name  = "${var.project_name}-api-${var.environment}"
  api_gateway_stage = var.environment

  # Lambda function configuration
  lambda_functions = [
    module.query_handler.function_name,
    module.document_processor.function_name,
    # module.authorizer.function_name,  # Using Cognito authorizer
    module.index_creator.function_name
  ]

  # Cost alert configuration
  cost_alert_threshold = var.cost_alert_threshold

  # X-Ray configuration
  enable_xray_tracing = var.enable_xray_tracing

  # Synthetics configuration
  enable_synthetics = var.enable_synthetics
  api_endpoint      = module.api_gateway.api_endpoint

  # Knowledge Base monitoring
  knowledge_base_id = module.bedrock.knowledge_base_id

  # Ensure Lambda functions are created first
  depends_on = [
    module.query_handler,
    module.document_processor,
    module.index_creator,
    # module.authorizer,  # Using Cognito authorizer
  ]
}

# Lambda function - Index creator (special purpose)
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