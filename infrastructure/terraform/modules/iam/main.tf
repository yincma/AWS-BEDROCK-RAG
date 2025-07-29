# IAM Module - IAM 角色和策略管理

# Lambda 执行角色
resource "aws_iam_role" "lambda_execution" {
  count = var.create_lambda_role ? 1 : 0

  name               = "${var.name_prefix}-lambda-execution-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = var.tags
}

# Lambda 假设角色策略
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# Lambda 基础执行策略
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  count = var.create_lambda_role ? 1 : 0

  role       = aws_iam_role.lambda_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda VPC 执行策略（如果启用）
resource "aws_iam_role_policy_attachment" "lambda_vpc_execution" {
  count = var.create_lambda_role && var.enable_vpc_config ? 1 : 0

  role       = aws_iam_role.lambda_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Lambda X-Ray 追踪策略（如果启用）
resource "aws_iam_role_policy_attachment" "lambda_xray" {
  count = var.create_lambda_role && var.enable_xray_tracing ? 1 : 0

  role       = aws_iam_role.lambda_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# 自定义 Lambda 策略
resource "aws_iam_role_policy" "lambda_custom" {
  count = var.create_lambda_role && length(var.lambda_policy_statements) > 0 ? 1 : 0

  name   = "${var.name_prefix}-lambda-custom-policy"
  role   = aws_iam_role.lambda_execution[0].id
  policy = data.aws_iam_policy_document.lambda_custom[0].json
}

# 自定义策略文档
data "aws_iam_policy_document" "lambda_custom" {
  count = var.create_lambda_role && length(var.lambda_policy_statements) > 0 ? 1 : 0

  dynamic "statement" {
    for_each = var.lambda_policy_statements

    content {
      effect    = lookup(statement.value, "effect", "Allow")
      actions   = statement.value.actions
      resources = statement.value.resources

      dynamic "condition" {
        for_each = lookup(statement.value, "conditions", [])

        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }
}

# API Gateway 执行角色
resource "aws_iam_role" "api_gateway" {
  count = var.create_api_gateway_role ? 1 : 0

  name               = "${var.name_prefix}-api-gateway-role"
  assume_role_policy = data.aws_iam_policy_document.api_gateway_assume_role.json

  tags = var.tags
}

# API Gateway 假设角色策略
data "aws_iam_policy_document" "api_gateway_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# API Gateway CloudWatch Logs 策略
resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch" {
  count = var.create_api_gateway_role ? 1 : 0

  role       = aws_iam_role.api_gateway[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

# S3 复制角色（用于跨区域复制）
resource "aws_iam_role" "s3_replication" {
  count = var.create_s3_replication_role ? 1 : 0

  name               = "${var.name_prefix}-s3-replication-role"
  assume_role_policy = data.aws_iam_policy_document.s3_replication_assume_role.json

  tags = var.tags
}

# S3 复制假设角色策略
data "aws_iam_policy_document" "s3_replication_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# S3 复制策略
resource "aws_iam_role_policy" "s3_replication" {
  count = var.create_s3_replication_role ? 1 : 0

  name = "${var.name_prefix}-s3-replication-policy"
  role = aws_iam_role.s3_replication[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = var.s3_source_bucket_arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Resource = "${var.s3_source_bucket_arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Resource = "${var.s3_destination_bucket_arn}/*"
      }
    ]
  })
}

# 服务账号角色（用于 Kubernetes/EKS）
resource "aws_iam_role" "service_account" {
  count = var.create_service_account_role ? 1 : 0

  name = "${var.name_prefix}-service-account-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${var.oidc_provider_url}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
          }
        }
      }
    ]
  })

  tags = var.tags
}