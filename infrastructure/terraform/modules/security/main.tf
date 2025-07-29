# Lambda Execution Role
resource "aws_iam_role" "lambda_execution" {
  name = "${var.project_name}-lambda-execution-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags
}

# Lambda Execution Policy
resource "aws_iam_role_policy" "lambda_execution" {
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:ListFoundationModels"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:RetrieveAndGenerate",
          "bedrock:Retrieve",
          "bedrock:GetKnowledgeBase",
          "bedrock:ListIngestionJobs",
          "bedrock:GetIngestionJob",
          "bedrock:StartIngestionJob"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock-agent:Retrieve",
          "bedrock-agent:RetrieveAndGenerate",
          "bedrock-agent:GetKnowledgeBase",
          "bedrock-agent:ListIngestionJobs",
          "bedrock-agent:GetIngestionJob",
          "bedrock-agent:StartIngestionJob",
          "bedrock-agent:GetDataSource",
          "bedrock-agent:ListDataSources"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:HeadBucket",
          "s3:HeadObject",
          "s3:ListBucketVersions"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cognito-idp:AdminGetUser",
          "cognito-idp:AdminListGroupsForUser"
        ]
        Resource = var.cognito_user_pool_arn != "" ? var.cognito_user_pool_arn : "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueAttributes",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach VPC Access Policy
resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Security Group for Lambda Functions
resource "aws_security_group" "lambda" {
  name        = "${var.project_name}-lambda-sg-${var.environment}"
  description = "Security group for Lambda functions"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-lambda-sg-${var.environment}"
    }
  )
}

# KMS Key for Encryption
resource "aws_kms_key" "main" {
  description             = "${var.project_name} ${var.environment} encryption key"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-kms-${var.environment}"
    }
  )
}

# KMS Key Alias
resource "aws_kms_alias" "main" {
  name          = "alias/${var.project_name}-${var.environment}"
  target_key_id = aws_kms_key.main.key_id
}