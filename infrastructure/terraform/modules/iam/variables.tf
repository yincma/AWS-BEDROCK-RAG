variable "name_prefix" {
  description = "资源名称前缀"
  type        = string
}

variable "tags" {
  description = "资源标签"
  type        = map(string)
  default     = {}
}

# Lambda 角色相关变量
variable "create_lambda_role" {
  description = "是否创建 Lambda 执行角色"
  type        = bool
  default     = true
}

variable "enable_vpc_config" {
  description = "Lambda 是否需要 VPC 访问"
  type        = bool
  default     = false
}

variable "enable_xray_tracing" {
  description = "是否启用 X-Ray 追踪"
  type        = bool
  default     = true
}

variable "lambda_policy_statements" {
  description = "Lambda 自定义策略语句"
  type = list(object({
    effect    = optional(string, "Allow")
    actions   = list(string)
    resources = list(string)
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })), [])
  }))
  default = []
}

# API Gateway 角色相关变量
variable "create_api_gateway_role" {
  description = "是否创建 API Gateway 角色"
  type        = bool
  default     = false
}

# S3 复制角色相关变量
variable "create_s3_replication_role" {
  description = "是否创建 S3 复制角色"
  type        = bool
  default     = false
}

variable "s3_source_bucket_arn" {
  description = "S3 源桶 ARN"
  type        = string
  default     = ""
}

variable "s3_destination_bucket_arn" {
  description = "S3 目标桶 ARN"
  type        = string
  default     = ""
}

# 服务账号角色相关变量
variable "create_service_account_role" {
  description = "是否创建服务账号角色"
  type        = bool
  default     = false
}

variable "oidc_provider_arn" {
  description = "OIDC Provider ARN"
  type        = string
  default     = ""
}

variable "oidc_provider_url" {
  description = "OIDC Provider URL"
  type        = string
  default     = ""
}

variable "namespace" {
  description = "Kubernetes 命名空间"
  type        = string
  default     = "default"
}

variable "service_account_name" {
  description = "服务账号名称"
  type        = string
  default     = ""
}