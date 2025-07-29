# Lambda function to create OpenSearch index
resource "aws_lambda_function" "opensearch_index_creator" {
  count = var.enable_bedrock_knowledge_base ? 1 : 0

  filename      = data.archive_file.index_creator_zip[0].output_path
  function_name = "${var.project_name}-opensearch-index-creator-${var.environment}"
  role          = aws_iam_role.index_creator_lambda[0].arn
  handler       = "index_creator.handler"
  runtime       = "python3.9"
  timeout       = 60

  layers = [aws_lambda_layer_version.index_creator_deps[0].arn]

  environment {
    variables = {
      COLLECTION_ENDPOINT = aws_opensearchserverless_collection.knowledge_base[0].collection_endpoint
      INDEX_NAME          = "bedrock-knowledge-base-index"
      REGION              = var.aws_region
    }
  }

  depends_on = [
    aws_opensearchserverless_collection.knowledge_base,
    aws_iam_role_policy.index_creator_lambda,
    aws_lambda_layer_version.index_creator_deps
  ]
}

# IAM role for Lambda
resource "aws_iam_role" "index_creator_lambda" {
  count = var.enable_bedrock_knowledge_base ? 1 : 0

  name = "${var.project_name}-index-creator-lambda-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# IAM policy for Lambda
resource "aws_iam_role_policy" "index_creator_lambda" {
  count = var.enable_bedrock_knowledge_base ? 1 : 0

  role = aws_iam_role.index_creator_lambda[0].id

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
          "aoss:APIAccessAll",
          "aoss:*"
        ]
        Resource = [
          aws_opensearchserverless_collection.knowledge_base[0].arn,
          "${aws_opensearchserverless_collection.knowledge_base[0].arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "es:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda layer for dependencies
resource "aws_lambda_layer_version" "index_creator_deps" {
  count = var.enable_bedrock_knowledge_base ? 1 : 0

  filename   = data.archive_file.layer_zip[0].output_path
  layer_name = "${var.project_name}-index-creator-deps-${var.environment}"

  compatible_runtimes = ["python3.9"]

  depends_on = [data.archive_file.layer_zip]
}

# Build Lambda layer
resource "null_resource" "build_layer" {
  count = var.enable_bedrock_knowledge_base ? 1 : 0

  triggers = {
    requirements = filemd5("${path.module}/lambda_requirements.txt")
  }

  provisioner "local-exec" {
    command = <<EOF
      mkdir -p ${path.module}/layer/python
      pip install -r ${path.module}/lambda_requirements.txt -t ${path.module}/layer/python --quiet
    EOF
  }
}

# Package Lambda layer
data "archive_file" "layer_zip" {
  count = var.enable_bedrock_knowledge_base ? 1 : 0

  type        = "zip"
  source_dir  = "${path.module}/layer"
  output_path = "${path.module}/layer.zip"

  depends_on = [null_resource.build_layer]
}

# Lambda deployment package
data "archive_file" "index_creator_zip" {
  count = var.enable_bedrock_knowledge_base ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/index_creator.zip"

  source {
    content  = file("${path.module}/index_creator.py")
    filename = "index_creator.py"
  }
}

# Lambda invocation to create index
resource "aws_lambda_invocation" "create_index" {
  count = var.enable_bedrock_knowledge_base ? 1 : 0

  function_name = aws_lambda_function.opensearch_index_creator[0].function_name

  input = jsonencode({
    action = "create"
  })

  depends_on = [
    aws_lambda_function.opensearch_index_creator
  ]
}