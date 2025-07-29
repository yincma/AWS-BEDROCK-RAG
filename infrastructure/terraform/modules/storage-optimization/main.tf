# Storage Cost Optimization Module
# Implements comprehensive storage cost optimization strategies

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
  }
}

# S3 Lifecycle Configuration
module "s3_lifecycle" {
  source = "./s3-lifecycle"

  buckets                    = var.s3_buckets
  environment                = var.environment
  project_name               = var.project_name
  enable_intelligent_tiering = var.enable_intelligent_tiering
  enable_inventory           = var.enable_inventory
  enable_storage_lens        = var.enable_storage_lens
  common_tags                = var.common_tags
}

# CloudWatch Logs Optimization
module "logs_optimization" {
  source = "./logs-optimization"

  log_groups                  = var.log_groups
  environment                 = var.environment
  project_name                = var.project_name
  enable_metric_filters       = var.enable_metric_filters
  enable_subscription_filters = var.enable_subscription_filters
  kms_key_id                  = var.kms_key_id
  common_tags                 = var.common_tags
}

# Data Compression and Archival
module "data_compression" {
  source = "./data-compression"

  compression_enabled_buckets = var.compression_enabled_buckets
  archive_enabled_buckets     = var.archive_enabled_buckets
  environment                 = var.environment
  project_name                = var.project_name
  lambda_runtime              = var.lambda_runtime
  common_tags                 = var.common_tags
}

# Cost Monitoring and Alerts
module "cost_monitoring" {
  source = "./cost-monitoring"

  storage_budget_amount = var.storage_budget_amount
  logs_budget_amount    = var.logs_budget_amount
  alert_email           = var.alert_email
  environment           = var.environment
  project_name          = var.project_name
  common_tags           = var.common_tags
}

# Outputs
output "lifecycle_configurations" {
  description = "S3 lifecycle configurations"
  value       = module.s3_lifecycle.lifecycle_configurations
}

output "log_group_configurations" {
  description = "CloudWatch log group configurations"
  value       = module.logs_optimization.log_group_configurations
}

output "compression_functions" {
  description = "Data compression Lambda functions"
  value       = module.data_compression.compression_functions
}

output "cost_alerts" {
  description = "Cost monitoring alerts"
  value       = module.cost_monitoring.alerts
}

output "optimization_summary" {
  description = "Summary of storage optimization configurations"
  value = {
    s3_lifecycle_rules_count    = module.s3_lifecycle.lifecycle_rules_count
    intelligent_tiering_enabled = module.s3_lifecycle.intelligent_tiering_count
    log_groups_with_retention   = module.logs_optimization.optimized_log_groups_count
    compression_enabled_buckets = length(var.compression_enabled_buckets)
    total_estimated_savings = sum([
      module.s3_lifecycle.estimated_monthly_savings,
      module.logs_optimization.estimated_monthly_savings,
      module.data_compression.estimated_monthly_savings
    ])
  }
}