# Tags Module - 统一标签管理
# 提供标准化的标签集合，确保所有资源都有一致的标签

locals {
  # 获取当前时间戳
  timestamp = formatdate("YYYY-MM-DD", timestamp())

  # 默认标签
  default_tags = {
    Project         = var.project_name
    Environment     = var.environment
    ManagedBy       = "Terraform"
    TerraformModule = "tags"
    CreatedDate     = local.timestamp
    Owner           = var.owner
    CostCenter      = var.cost_center
    Version         = var.project_version
  }

  # 合规性标签
  compliance_tags = var.enable_compliance_tags ? {
    DataClassification = var.data_classification
    Compliance         = var.compliance_framework
    BackupRequired     = var.backup_required ? "true" : "false"
    RetentionPeriod    = var.retention_period
  } : {}

  # 技术标签
  technical_tags = var.enable_technical_tags ? {
    Stack             = var.stack_name
    Component         = var.component_name
    DeploymentMethod  = var.deployment_method
    MonitoringEnabled = var.monitoring_enabled ? "true" : "false"
  } : {}

  # 自动化标签
  automation_tags = var.enable_automation_tags ? {
    AutoScaling       = var.auto_scaling_enabled ? "true" : "false"
    AutoShutdown      = var.auto_shutdown_enabled ? "true" : "false"
    AutoBackup        = var.auto_backup_enabled ? "true" : "false"
    MaintenanceWindow = var.maintenance_window
  } : {}
}

# 输出完整的标签集合
output "common_tags" {
  description = "所有通用标签的组合"
  value = merge(
    local.default_tags,
    local.compliance_tags,
    local.technical_tags,
    local.automation_tags,
    var.additional_tags
  )
}

# 输出特定类别的标签
output "default_tags" {
  description = "默认标签集合"
  value       = local.default_tags
}

output "compliance_tags" {
  description = "合规性相关标签"
  value       = local.compliance_tags
}

output "technical_tags" {
  description = "技术相关标签"
  value       = local.technical_tags
}

output "automation_tags" {
  description = "自动化相关标签"
  value       = local.automation_tags
}