package terraform.analysis

# 成本和性能策略配置
# 版本: v1.0
# 最后更新: 2025-07-26

# 策略版本管理
policy_version := {
	"cost_policies": "1.0.0",
	"performance_policies": "1.0.0",
	"compliance_policies": "1.0.0",
	"effective_date": "2025-07-26",
}

# 全局配置
global_config := {
	"organization": "enterprise-rag",
	"default_region": "us-east-1",
	"allowed_regions": ["us-east-1", "us-west-2", "ap-northeast-1"],
	"policy_enforcement_level": "strict", # strict/warning/advisory
	"exception_expiry_days": 90,
}

# 环境特定配置
environment_config := {
	"dev": {
		"cost_limit_monthly": 500,
		"cost_limit_daily": 20,
		"performance_requirements": "basic",
		"required_tags": ["Project", "Environment", "Owner"],
		"allow_exceptions": true,
	},
	"staging": {
		"cost_limit_monthly": 1000,
		"cost_limit_daily": 35,
		"performance_requirements": "standard",
		"required_tags": ["Project", "Environment", "Owner", "CostCenter"],
		"allow_exceptions": true,
	},
	"prod": {
		"cost_limit_monthly": 5000,
		"cost_limit_daily": 170,
		"performance_requirements": "high",
		"required_tags": ["Project", "Environment", "Owner", "CostCenter", "BackupPolicy"],
		"allow_exceptions": false,
	},
}

# 服务特定阈值配置
service_thresholds := {
	"lambda": {
		"dev": {"memory_mb": 1024, "timeout_sec": 300, "concurrency": 100},
		"staging": {"memory_mb": 1536, "timeout_sec": 600, "concurrency": 500},
		"prod": {"memory_mb": 3008, "timeout_sec": 900, "concurrency": 1000},
	},
	"opensearch": {
		"dev": {"max_ocu": 4, "max_nodes": 2},
		"staging": {"max_ocu": 8, "max_nodes": 4},
		"prod": {"max_ocu": 20, "max_nodes": 10},
	},
	"s3": {
		"max_bucket_size_gb": 1000,
		"lifecycle_required": true,
		"encryption_required": true,
	},
	"cloudfront": {
		"dev": {"price_class": "PriceClass_100"},
		"staging": {"price_class": "PriceClass_200"},
		"prod": {"price_class": "PriceClass_All"},
	},
}

# 豁免配置
exemption_config := {
	"approval_required": true,
	"max_duration_days": 180,
	"auto_expiry": true,
	"notification_days_before_expiry": 14,
	"allowed_exemption_reasons": [
		"security-assessment-approved",
		"business-critical-requirement",
		"technical-limitation",
		"legacy-system-migration",
		"cost-benefit-analysis-approved",
	],
}

# 告警级别配置
alert_levels := {
	"cost": {
		"critical": {"threshold_percent": 100, "action": "block"},
		"warning": {"threshold_percent": 80, "action": "warn"},
		"info": {"threshold_percent": 60, "action": "notify"},
	},
	"performance": {
		"critical": {"action": "block", "required_fix": true},
		"warning": {"action": "warn", "required_fix": false},
		"info": {"action": "notify", "required_fix": false},
	},
	"compliance": {
		"critical": {"action": "block", "required_fix": true},
		"warning": {"action": "warn", "required_fix": false},
	},
}

# 监控和报告配置
monitoring_config := {
	"cost_tracking": {
		"enabled": true,
		"daily_reports": true,
		"monthly_reports": true,
		"alert_on_anomaly": true,
		"cost_allocation_tags": ["Project", "CostCenter", "Environment"],
	},
	"performance_monitoring": {
		"enabled": true,
		"metrics_retention_days": 90,
		"alert_on_degradation": true,
	},
	"compliance_audit": {
		"enabled": true,
		"weekly_reports": true,
		"violation_tracking": true,
	},
}

# 获取环境特定的成本限制
get_cost_limit(env, period) := limit if {
	env_config := environment_config[env]
	period == "monthly"
	limit := env_config.cost_limit_monthly
} else := limit if {
	env_config := environment_config[env]
	period == "daily"
	limit := env_config.cost_limit_daily
} else := 0

# 获取服务特定的阈值
get_service_threshold(service, env, metric) := threshold if {
	service_config := service_thresholds[service][env]
	threshold := service_config[metric]
} else := 0

# 检查是否允许豁免
allow_exceptions(env) if {
	env_config := environment_config[env]
	env_config.allow_exceptions == true
}

# 获取策略执行级别
get_enforcement_level := global_config.policy_enforcement_level

# 检查区域是否被允许
is_allowed_region(region) if {
	region in global_config.allowed_regions
}

# 检查豁免是否有效
is_exemption_valid(resource, policy_id) if {
	has_exception(resource, policy_id)
	expiry := resource.values.tags["exception-expires"]
	reason := resource.values.tags["exception-reason"]

	# 检查过期时间
	# 简化的日期检查 - 实际实现中应该解析日期
	expiry > "2025-01-01"

	# 检查豁免原因是否在允许列表中
	reason in exemption_config.allowed_exemption_reasons
}
