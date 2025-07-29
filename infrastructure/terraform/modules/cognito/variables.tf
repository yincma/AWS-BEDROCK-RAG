variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "enable_cognito" {
  description = "Enable Cognito User Pool"
  type        = bool
  default     = true
}

variable "cognito_callback_urls" {
  description = "Cognito callback URLs"
  type        = list(string)
  default     = []
}

variable "cognito_logout_urls" {
  description = "Cognito logout URLs"
  type        = list(string)
  default     = []
}

variable "cognito_password_minimum_length" {
  description = "Minimum password length"
  type        = number
  default     = 8
}

variable "cognito_mfa_configuration" {
  description = "MFA configuration (OFF, ON, OPTIONAL)"
  type        = string
  default     = "OFF"
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}