# Local variables for OpenSearch Serverless naming (must be lowercase alphanumeric only)
locals {
  # Remove hyphens from names to comply with OpenSearch Serverless naming requirements
  opensearch_collection_name      = replace("${var.project_name}-kb-collection-${var.environment}", "-", "")
  opensearch_security_policy_name = replace("${var.project_name}-kb-security-${var.environment}", "-", "")
  opensearch_network_policy_name  = replace("${var.project_name}-kb-network-${var.environment}", "-", "")
  opensearch_access_policy_name   = replace("${var.project_name}-kb-access-${var.environment}", "-", "")
}

# IAM Role for Bedrock Knowledge Base
resource "aws_iam_role" "bedrock_knowledge_base" {
  count = var.enable_bedrock_knowledge_base ? 1 : 0
  name  = "${var.project_name}-bedrock-kb-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "bedrock.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags
}

# IAM Policy for Bedrock Knowledge Base
resource "aws_iam_role_policy" "bedrock_knowledge_base" {
  count = var.enable_bedrock_knowledge_base ? 1 : 0
  role  = aws_iam_role.bedrock_knowledge_base[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketVersioning",
          "s3:ListBucketVersions"
        ]
        Resource = [
          var.document_bucket_arn,
          "${var.document_bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel"
        ]
        Resource = [
          "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.embedding_model_id}"
        ]
      }
    ]
  })
}

# Add OpenSearch permissions for Bedrock Knowledge Base
resource "aws_iam_role_policy" "bedrock_opensearch" {
  count = var.enable_bedrock_knowledge_base ? 1 : 0
  role  = aws_iam_role.bedrock_knowledge_base[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "aoss:APIAccessAll"
        ]
        Resource = [
          aws_opensearchserverless_collection.knowledge_base[0].arn,
          "${aws_opensearchserverless_collection.knowledge_base[0].arn}/*"
        ]
      }
    ]
  })
}

# OpenSearch Serverless Collection for Vector Store
resource "aws_opensearchserverless_collection" "knowledge_base" {
  count = var.enable_bedrock_knowledge_base ? 1 : 0

  name = local.opensearch_collection_name
  type = "VECTORSEARCH"

  depends_on = [
    aws_opensearchserverless_security_policy.knowledge_base,
    aws_opensearchserverless_security_policy.knowledge_base_network
  ]

  tags = var.common_tags

  # Note: After the collection is created, you need to create an index
  # This can be done using the AWS CLI or SDK after the collection is ACTIVE
}

# OpenSearch Serverless Security Policy
resource "aws_opensearchserverless_security_policy" "knowledge_base" {
  count = var.enable_bedrock_knowledge_base ? 1 : 0

  name = local.opensearch_security_policy_name
  type = "encryption"
  policy = jsonencode({
    Rules = [
      {
        Resource     = ["collection/${local.opensearch_collection_name}"]
        ResourceType = "collection"
      }
    ]
    AWSOwnedKey = true
  })

}

# OpenSearch Serverless Network Policy
resource "aws_opensearchserverless_security_policy" "knowledge_base_network" {
  count = var.enable_bedrock_knowledge_base ? 1 : 0

  name = local.opensearch_network_policy_name
  type = "network"
  policy = jsonencode([
    {
      Rules = [
        {
          Resource     = ["collection/${local.opensearch_collection_name}"]
          ResourceType = "collection"
        }
      ]
      AllowFromPublic = true
    }
  ])

}

# OpenSearch Serverless Access Policy
resource "aws_opensearchserverless_access_policy" "knowledge_base" {
  count = var.enable_bedrock_knowledge_base ? 1 : 0

  name = local.opensearch_access_policy_name
  type = "data"
  policy = jsonencode([
    {
      Rules = [
        {
          ResourceType = "collection"
          Resource     = ["collection/${local.opensearch_collection_name}"]
          Permission   = ["aoss:*"]
        },
        {
          ResourceType = "index"
          Resource     = ["index/${local.opensearch_collection_name}/*"]
          Permission   = ["aoss:*"]
        }
      ]
      Principal = [
        aws_iam_role.bedrock_knowledge_base[0].arn,
        aws_iam_role.index_creator_lambda[0].arn,
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root",
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/enterprise-rag-lambda-execution-dev"
      ]
    }
  ])

}

# Data source for current AWS account
data "aws_caller_identity" "current" {}

# Data source for embedding model
data "aws_bedrock_foundation_model" "embedding" {
  model_id = var.embedding_model_id
}

# Bedrock Knowledge Base
resource "aws_bedrockagent_knowledge_base" "main" {
  count = var.enable_bedrock_knowledge_base ? 1 : 0

  name        = "${var.project_name}-knowledge-base-${var.environment}"
  role_arn    = aws_iam_role.bedrock_knowledge_base[0].arn
  description = "RAG Knowledge Base for ${var.project_name} ${var.environment}"

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = data.aws_bedrock_foundation_model.embedding.model_arn
    }
  }

  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"
    opensearch_serverless_configuration {
      collection_arn    = aws_opensearchserverless_collection.knowledge_base[0].arn
      vector_index_name = "bedrock-knowledge-base-index"
      field_mapping {
        vector_field   = "bedrock-knowledge-base-vector"
        text_field     = "text"
        metadata_field = "metadata"
      }
    }
  }

  depends_on = [
    aws_opensearchserverless_access_policy.knowledge_base,
    aws_iam_role_policy.bedrock_opensearch,
    aws_lambda_invocation.create_index
  ]

  tags = var.common_tags
}

# S3 Data Source for Knowledge Base
resource "aws_bedrockagent_data_source" "s3" {
  count = var.enable_bedrock_knowledge_base ? 1 : 0

  knowledge_base_id = aws_bedrockagent_knowledge_base.main[0].id
  name              = "${var.project_name}-s3-datasource-${var.environment}"
  description       = "S3 data source for document ingestion"

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn = var.document_bucket_arn
      # Add document prefix configuration to ensure only documents/ directory is scanned
      inclusion_prefixes = ["documents/"]
    }
  }

  depends_on = [aws_bedrockagent_knowledge_base.main]
}

# Local values for outputs
locals {
  knowledge_base_id   = var.enable_bedrock_knowledge_base ? aws_bedrockagent_knowledge_base.main[0].id : ""
  knowledge_base_arn  = var.enable_bedrock_knowledge_base ? aws_bedrockagent_knowledge_base.main[0].arn : ""
  data_source_id      = var.enable_bedrock_knowledge_base ? aws_bedrockagent_data_source.s3[0].data_source_id : ""
  opensearch_endpoint = var.enable_bedrock_knowledge_base ? aws_opensearchserverless_collection.knowledge_base[0].collection_endpoint : ""
}