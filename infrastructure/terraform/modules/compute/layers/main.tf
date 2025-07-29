# Lambda Layer for OpenSearch dependencies
resource "aws_lambda_layer_version" "opensearch" {
  filename                 = var.layer_source_dir != "" ? "${var.layer_source_dir}/opensearch-layer.zip" : "${path.module}/../../../../dist/opensearch-layer.zip"
  layer_name               = "${var.project_name}-opensearch-layer-${var.environment}"
  description              = "OpenSearch client and dependencies"
  compatible_runtimes      = [var.python_runtime]
  compatible_architectures = ["x86_64", "arm64"]

  lifecycle {
    create_before_destroy = true
  }
}

# Lambda Layer for Bedrock dependencies
resource "aws_lambda_layer_version" "bedrock" {
  filename                 = var.layer_source_dir != "" ? "${var.layer_source_dir}/bedrock-layer.zip" : "${path.module}/../../../../dist/bedrock-layer.zip"
  layer_name               = "${var.project_name}-bedrock-layer-${var.environment}"
  description              = "Bedrock client and dependencies"
  compatible_runtimes      = [var.python_runtime]
  compatible_architectures = ["x86_64", "arm64"]

  lifecycle {
    create_before_destroy = true
  }
}

# Lambda Layer for common utilities
resource "aws_lambda_layer_version" "common" {
  filename                 = var.layer_source_dir != "" ? "${var.layer_source_dir}/common-layer.zip" : "${path.module}/../../../../dist/common-layer.zip"
  layer_name               = "${var.project_name}-common-layer-${var.environment}"
  description              = "Common utilities and dependencies"
  compatible_runtimes      = [var.python_runtime]
  compatible_architectures = ["x86_64", "arm64"]

  lifecycle {
    create_before_destroy = true
  }
}