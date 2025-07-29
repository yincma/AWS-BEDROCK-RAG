# Variables for Cost Monitoring Submodule

variable "storage_budget_amount" {
  description = "Monthly budget for S3 storage"
  type        = number
}

variable "logs_budget_amount" {
  description = "Monthly budget for CloudWatch logs"
  type        = number
}

variable "alert_email" {
  description = "Email for cost alerts"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "common_tags" {
  description = "Common tags"
  type        = map(string)
}