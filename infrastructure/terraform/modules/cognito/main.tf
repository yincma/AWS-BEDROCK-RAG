# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  count = var.enable_cognito ? 1 : 0
  name  = "${var.project_name}-users-${var.environment}"

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  # Enable self-service sign-up
  username_configuration {
    case_sensitive = false
  }

  # Enable email verification
  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "${var.project_name} - Verify your email"
    email_message        = "Your verification code is {####}"
  }

  # Configure admin create user
  admin_create_user_config {
    allow_admin_create_user_only = false # Allow self-service sign-up

    invite_message_template {
      email_subject = "${var.project_name} - Your temporary password"
      email_message = "Your username is {username} and temporary password is {####}"
      sms_message   = "Your username is {username} and temporary password is {####}"
    }
  }

  password_policy {
    minimum_length                   = var.cognito_password_minimum_length
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  user_attribute_update_settings {
    attributes_require_verification_before_update = ["email"]
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  mfa_configuration = var.cognito_mfa_configuration

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-cognito-user-pool-${var.environment}"
    }
  )
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  count        = var.enable_cognito ? 1 : 0
  name         = "${var.project_name}-client-${var.environment}"
  user_pool_id = aws_cognito_user_pool.main[0].id

  generate_secret               = false
  refresh_token_validity        = 30
  access_token_validity         = 1
  id_token_validity             = 1
  enable_token_revocation       = true
  prevent_user_existence_errors = "ENABLED"

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]

  callback_urls = var.cognito_callback_urls
  logout_urls   = var.cognito_logout_urls

  supported_identity_providers = ["COGNITO"]

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_CUSTOM_AUTH",
    "ALLOW_ADMIN_USER_PASSWORD_AUTH"
  ]

  read_attributes = [
    "email",
    "email_verified",
    "name",
    "preferred_username",
    "profile"
  ]

  write_attributes = [
    "email",
    "name",
    "preferred_username",
    "profile"
  ]
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
  count        = var.enable_cognito ? 1 : 0
  domain       = "${var.project_name}-${var.environment}-${substr(md5(timestamp()), 0, 8)}"
  user_pool_id = aws_cognito_user_pool.main[0].id
}