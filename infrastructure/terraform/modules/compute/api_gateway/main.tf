# API Gateway REST API
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.project_name}-${var.environment}"
  description = "API Gateway for ${var.project_name} ${var.environment}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-api-${var.environment}"
    }
  )
}

# API Gateway Resources
resource "aws_api_gateway_resource" "query" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "query"
}

resource "aws_api_gateway_resource" "documents" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "documents"
}

resource "aws_api_gateway_resource" "document_item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.documents.id
  path_part   = "{documentId}"
}

resource "aws_api_gateway_resource" "index" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "index"
}

resource "aws_api_gateway_resource" "query_status" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.query.id
  path_part   = "status"
}

resource "aws_api_gateway_resource" "upload" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "upload"
}

# API Gateway Methods
resource "aws_api_gateway_method" "query_post" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.query.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id

  request_parameters = {
    "method.request.header.Authorization" = true
  }
}

resource "aws_api_gateway_method" "documents_post" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.documents.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id

  request_parameters = {
    "method.request.header.Authorization" = true
  }
}

resource "aws_api_gateway_method" "documents_get" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.documents.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id

  request_parameters = {
    "method.request.header.Authorization" = true
  }
}

resource "aws_api_gateway_method" "document_get" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.document_item.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id

  request_parameters = {
    "method.request.header.Authorization" = true
  }
}

resource "aws_api_gateway_method" "document_delete" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.document_item.id
  http_method   = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id

  request_parameters = {
    "method.request.header.Authorization" = true
  }
}

resource "aws_api_gateway_method" "index_post" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.index.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id

  request_parameters = {
    "method.request.header.Authorization" = true
  }
}

resource "aws_api_gateway_method" "query_status_get" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.query_status.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id

  request_parameters = {
    "method.request.header.Authorization" = true
  }
}

resource "aws_api_gateway_method" "upload_post" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.upload.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id

  request_parameters = {
    "method.request.header.Authorization" = true
  }
}

# Lambda Integrations
resource "aws_api_gateway_integration" "query_post" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.query.id
  http_method = aws_api_gateway_method.query_post.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_function_invoke_arns["query_handler"]
}

resource "aws_api_gateway_integration" "documents_post" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.documents.id
  http_method = aws_api_gateway_method.documents_post.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_function_invoke_arns["document_processor"]
}

resource "aws_api_gateway_integration" "documents_get" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.documents.id
  http_method = aws_api_gateway_method.documents_get.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_function_invoke_arns["document_processor"]
}

resource "aws_api_gateway_integration" "document_get" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.document_item.id
  http_method = aws_api_gateway_method.document_get.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_function_invoke_arns["document_processor"]
}

resource "aws_api_gateway_integration" "document_delete" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.document_item.id
  http_method = aws_api_gateway_method.document_delete.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_function_invoke_arns["document_processor"]
}

resource "aws_api_gateway_integration" "index_post" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.index.id
  http_method = aws_api_gateway_method.index_post.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_function_invoke_arns["index_creator"]
}

resource "aws_api_gateway_integration" "query_status_get" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.query_status.id
  http_method = aws_api_gateway_method.query_status_get.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_function_invoke_arns["query_handler"]
}

resource "aws_api_gateway_integration" "upload_post" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.upload.id
  http_method = aws_api_gateway_method.upload_post.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_function_invoke_arns["document_processor"]
}

# API Gateway Authorizer
# Commented out - replaced by Cognito authorizer
# resource "aws_api_gateway_authorizer" "main" {
#   name                   = "${var.project_name}-authorizer-${var.environment}"
#   rest_api_id            = aws_api_gateway_rest_api.main.id
#   authorizer_uri         = var.lambda_function_invoke_arns["authorizer"]
#   authorizer_credentials = aws_iam_role.api_gateway_authorizer.arn
#   type                   = "TOKEN"
#   identity_source        = "method.request.header.Authorization"
#   authorizer_result_ttl_in_seconds = 300
# }

# Commented out - not needed for Cognito authorizer
# # IAM Role for API Gateway Authorizer
# resource "aws_iam_role" "api_gateway_authorizer" {
#   name = "${var.project_name}-api-gateway-authorizer-${var.environment}"
# 
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRole"
#         Effect = "Allow"
#         Principal = {
#           Service = "apigateway.amazonaws.com"
#         }
#       }
#     ]
#   })
# 
#   tags = var.common_tags
# }
# 
# resource "aws_iam_role_policy" "api_gateway_authorizer" {
#   role = aws_iam_role.api_gateway_authorizer.id
# 
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Action = "lambda:InvokeFunction"
#         Resource = var.lambda_function_arns["authorizer"]
#       }
#     ]
#   })
# }

# CORS Configuration
locals {
  cors_resources = {
    query         = aws_api_gateway_resource.query
    query_status  = aws_api_gateway_resource.query_status
    documents     = aws_api_gateway_resource.documents
    document_item = aws_api_gateway_resource.document_item
    index         = aws_api_gateway_resource.index
    upload        = aws_api_gateway_resource.upload
  }

  # Define all HTTP methods that need CORS support
  http_methods = {
    query_post       = { resource = aws_api_gateway_resource.query, method = aws_api_gateway_method.query_post }
    query_status_get = { resource = aws_api_gateway_resource.query_status, method = aws_api_gateway_method.query_status_get }
    documents_post   = { resource = aws_api_gateway_resource.documents, method = aws_api_gateway_method.documents_post }
    documents_get    = { resource = aws_api_gateway_resource.documents, method = aws_api_gateway_method.documents_get }
    document_get     = { resource = aws_api_gateway_resource.document_item, method = aws_api_gateway_method.document_get }
    document_delete  = { resource = aws_api_gateway_resource.document_item, method = aws_api_gateway_method.document_delete }
    index_post       = { resource = aws_api_gateway_resource.index, method = aws_api_gateway_method.index_post }
    upload_post      = { resource = aws_api_gateway_resource.upload, method = aws_api_gateway_method.upload_post }
  }

  # Status codes to configure for CORS
  status_codes = ["200", "400", "401", "403", "500"]
}

# OPTIONS methods for all resources
resource "aws_api_gateway_method" "options" {
  for_each      = var.enable_cors ? local.cors_resources : {}
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = each.value.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options" {
  for_each    = var.enable_cors ? local.cors_resources : {}
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = each.value.id
  http_method = aws_api_gateway_method.options[each.key].http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = jsonencode({
      statusCode = 200
    })
  }
}

resource "aws_api_gateway_method_response" "options" {
  for_each    = var.enable_cors ? local.cors_resources : {}
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = each.value.id
  http_method = aws_api_gateway_method.options[each.key].http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "options" {
  for_each    = var.enable_cors ? local.cors_resources : {}
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = each.value.id
  http_method = aws_api_gateway_method.options[each.key].http_method
  status_code = aws_api_gateway_method_response.options[each.key].status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS,POST,PUT,DELETE'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# Method Responses for all HTTP methods (to ensure CORS headers are returned)
resource "aws_api_gateway_method_response" "http_methods" {
  for_each = var.enable_cors ? merge([
    for method_key, method_config in local.http_methods : {
      for status in local.status_codes : "${method_key}_${status}" => {
        rest_api_id = aws_api_gateway_rest_api.main.id
        resource_id = method_config.resource.id
        http_method = method_config.method.http_method
        status_code = status
      }
    }
  ]...) : {}

  rest_api_id = each.value.rest_api_id
  resource_id = each.value.resource_id
  http_method = each.value.http_method
  status_code = each.value.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

# Integration Responses for all HTTP methods (to map CORS headers)
resource "aws_api_gateway_integration_response" "http_methods" {
  for_each = var.enable_cors ? merge([
    for method_key, method_config in local.http_methods : {
      for status in local.status_codes : "${method_key}_${status}" => {
        rest_api_id = aws_api_gateway_rest_api.main.id
        resource_id = method_config.resource.id
        http_method = method_config.method.http_method
        status_code = status
      }
    }
  ]...) : {}

  rest_api_id = each.value.rest_api_id
  resource_id = each.value.resource_id
  http_method = each.value.http_method
  status_code = each.value.status_code

  # Use selection pattern to match Lambda error responses
  selection_pattern = each.value.status_code == "200" ? "" : (
    each.value.status_code == "400" ? ".*[Bad Request|Invalid].*" :
    each.value.status_code == "401" ? ".*[Unauthorized|Token].*" :
    each.value.status_code == "403" ? ".*Forbidden.*" :
    each.value.status_code == "500" ? ".*[Error|Exception].*" : ""
  )

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = var.cors_allowed_origins[0] == "*" ? "'*'" : "'${join(",", var.cors_allowed_origins)}'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS,POST,PUT,DELETE'"
  }

  depends_on = [aws_api_gateway_method_response.http_methods]
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  # Trigger redeployment when Lambda code or API configuration changes
  triggers = {
    # Redeploy when Lambda function code changes
    query_handler_hash      = var.lambda_source_code_hashes["query_handler"]
    document_processor_hash = var.lambda_source_code_hashes["document_processor"]
    # authorizer_hash         = var.lambda_source_code_hashes["authorizer"]  # Using Cognito authorizer
    index_creator_hash = var.lambda_source_code_hashes["index_creator"]

    # Also redeploy when API Gateway configuration changes
    api_configuration = sha256(jsonencode([
      aws_api_gateway_resource.query.id,
      aws_api_gateway_resource.documents.id,
      aws_api_gateway_resource.index.id,
      aws_api_gateway_method.query_post.id,
      aws_api_gateway_method.documents_post.id,
      aws_api_gateway_method.documents_get.id,
      aws_api_gateway_method.index_post.id,
      aws_api_gateway_integration.query_post.id,
      aws_api_gateway_integration.documents_post.id,
      aws_api_gateway_integration.documents_get.id,
      aws_api_gateway_integration.index_post.id
    ]))
  }

  # Ensure all resources are created before deployment
  depends_on = [
    aws_api_gateway_resource.query,
    aws_api_gateway_resource.documents,
    aws_api_gateway_resource.index,
    aws_api_gateway_method.query_post,
    aws_api_gateway_method.documents_post,
    aws_api_gateway_method.documents_get,
    aws_api_gateway_method.index_post,
    aws_api_gateway_integration.query_post,
    aws_api_gateway_integration.documents_post,
    aws_api_gateway_integration.documents_get,
    aws_api_gateway_integration.index_post,
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway Stage
resource "aws_api_gateway_stage" "main" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = var.environment

  xray_tracing_enabled = true

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-api-stage-${var.environment}"
    }
  )
}

# Lambda Permissions
resource "aws_lambda_permission" "api_gateway_query" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_names["query_handler"]
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "api_gateway_documents" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_names["document_processor"]
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

# Commented out - not needed for Cognito authorizer
# resource "aws_lambda_permission" "api_gateway_authorizer" {
#   statement_id  = "AllowAPIGatewayInvoke"
#   action        = "lambda:InvokeFunction"
#   function_name = var.lambda_function_names["authorizer"]
#   principal     = "apigateway.amazonaws.com"
#   source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
# }

resource "aws_lambda_permission" "api_gateway_index" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_names["index_creator"]
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

# Gateway Responses for CORS
resource "aws_api_gateway_gateway_response" "cors_4xx" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  response_type = "DEFAULT_4XX"

  response_parameters = {
    "gatewayresponse.header.Access-Control-Allow-Origin"  = "'*'"
    "gatewayresponse.header.Access-Control-Allow-Methods" = "'*'"
    "gatewayresponse.header.Access-Control-Allow-Headers" = "'*'"
  }
}

resource "aws_api_gateway_gateway_response" "cors_5xx" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  response_type = "DEFAULT_5XX"

  response_parameters = {
    "gatewayresponse.header.Access-Control-Allow-Origin"  = "'*'"
    "gatewayresponse.header.Access-Control-Allow-Methods" = "'*'"
    "gatewayresponse.header.Access-Control-Allow-Headers" = "'*'"
  }
}

resource "aws_api_gateway_gateway_response" "cors_unauthorized" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  response_type = "UNAUTHORIZED"

  response_parameters = {
    "gatewayresponse.header.Access-Control-Allow-Origin"  = "'*'"
    "gatewayresponse.header.Access-Control-Allow-Methods" = "'*'"
    "gatewayresponse.header.Access-Control-Allow-Headers" = "'*'"
  }
}

resource "aws_api_gateway_gateway_response" "cors_access_denied" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  response_type = "ACCESS_DENIED"

  response_parameters = {
    "gatewayresponse.header.Access-Control-Allow-Origin"  = "'*'"
    "gatewayresponse.header.Access-Control-Allow-Methods" = "'*'"
    "gatewayresponse.header.Access-Control-Allow-Headers" = "'*'"
  }
}