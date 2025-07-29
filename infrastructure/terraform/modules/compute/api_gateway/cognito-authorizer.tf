# Cognito User Pool Authorizer to replace the custom Lambda authorizer

# Get Cognito User Pool ID from ARN
locals {
  # Extract User Pool ID from ARN
  # ARN format: arn:aws:cognito-idp:region:account:userpool/user-pool-id
  user_pool_id = split("/", var.cognito_user_pool_arn)[1]
}

# Create Cognito Authorizer
resource "aws_api_gateway_authorizer" "cognito" {
  name            = "${var.project_name}-cognito-authorizer-${var.environment}"
  rest_api_id     = aws_api_gateway_rest_api.main.id
  type            = "COGNITO_USER_POOLS"
  provider_arns   = [var.cognito_user_pool_arn]
  identity_source = "method.request.header.Authorization"

  # Optional: Configure token validation
  # authorizer_result_ttl_in_seconds = 300
}

# Output the new authorizer ID for use in methods
output "cognito_authorizer_id" {
  value       = aws_api_gateway_authorizer.cognito.id
  description = "ID of the Cognito authorizer"
}