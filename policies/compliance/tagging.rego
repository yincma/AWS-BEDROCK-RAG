package terraform.analysis

import future.keywords.contains
import future.keywords.if
import future.keywords.in

# 策略元数据
__rego__metadoc__ := {
	"id": "COMP-001",
	"title": "标签合规策略",
	"description": "确保所有AWS资源具有必需的标签，支持成本分配、资源管理和合规性要求",
	"severity": "HIGH",
	"category": "compliance",
}

# 必需标签配置
required_tags := {
	"global": [
		"Project", # 项目名称
		"Environment", # 环境 (dev/staging/prod)
		"Owner", # 资源负责人
		"CreatedBy", # 创建方式 (terraform/manual)
	],
	"production": [
		"Project",
		"Environment",
		"Owner",
		"CreatedBy",
		"CostCenter", # 成本中心
		"BackupPolicy", # 备份策略
		"MaintenanceWindow", # 维护窗口
	],
	"cost_tracking": [
		"Project",
		"CostCenter",
		"BusinessUnit",
		"Application",
	],
}

# 标签值规范
tag_value_patterns := {
	"Environment": "^(dev|development|staging|test|prod|production)$",
	"Owner": "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", # 邮箱格式
	"Project": "^[a-z0-9-]{3,30}$", # 小写字母、数字、连字符，3-30字符
	"CostCenter": "^CC-[0-9]{4,6}$", # CC-开头的4-6位数字
	"CreatedBy": "^(terraform|manual|automation)$",
}

# 必需标签资源类型
taggable_resources := {
	"aws_lambda_function",
	"aws_s3_bucket",
	"aws_opensearch_domain",
	"aws_opensearchserverless_collection",
	"aws_cloudfront_distribution",
	"aws_api_gateway_rest_api",
	"aws_cognito_user_pool",
	"aws_iam_role",
	"aws_cloudwatch_log_group",
	"aws_vpc",
	"aws_security_group",
	"aws_instance",
	"aws_ebs_volume",
	"aws_rds_instance",
	"aws_elasticache_cluster",
}

# 检查全局必需标签
deny contains msg if {
	resource := planned_resources[_]
	resource.type in taggable_resources
	existing_tags := {tag | resource.values.tags[tag]}
	missing_tags := {tag | tag := required_tags.global[_]; not tag in existing_tags}
	count(missing_tags) > 0
	not has_exception(resource, "COMP-001")

	msg := sprintf(
		"资源 '%s' 缺少必需标签: %v",
		[resource.address, missing_tags],
	)
}

# 检查生产环境额外标签
deny contains msg if {
	resource := planned_resources[_]
	resource.type in taggable_resources
	is_production(resource)
	existing_tags := {tag | resource.values.tags[tag]}
	missing_tags := {tag | tag := required_tags.production[_]; not tag in existing_tags}
	count(missing_tags) > 0
	not has_exception(resource, "COMP-001")

	msg := sprintf(
		"生产环境资源 '%s' 缺少必需标签: %v",
		[resource.address, missing_tags],
	)
}

# 检查成本追踪标签
deny contains msg if {
	resource := planned_resources[_]
	resource.type in cost_sensitive_resources
	existing_tags := {tag | resource.values.tags[tag]}
	missing_tags := {tag | tag := required_tags.cost_tracking[_]; not tag in existing_tags}
	count(missing_tags) > 2 # 允许缺少最多2个成本追踪标签
	not has_exception(resource, "COMP-001")

	msg := sprintf(
		"高成本资源 '%s' 缺少成本追踪标签: %v",
		[resource.address, missing_tags],
	)
}

# 高成本敏感资源
cost_sensitive_resources := {
	"aws_opensearch_domain",
	"aws_opensearchserverless_collection",
	"aws_instance",
	"aws_rds_instance",
	"aws_elasticache_cluster",
}

# 检查标签值格式
deny contains msg if {
	resource := planned_resources[_]
	resource.type in taggable_resources
	tag_name := {tag | resource.values.tags[tag]}[_]
	tag_name in tag_value_patterns
	tag_value := resource.values.tags[tag_name]
	not regex.match(tag_value_patterns[tag_name], tag_value)
	not has_exception(resource, "COMP-001")

	msg := sprintf(
		"资源 '%s' 标签 '%s' 值 '%s' 不符合格式要求",
		[resource.address, tag_name, tag_value],
	)
}

# 检查环境标签一致性
deny contains msg if {
	resource := planned_resources[_]
	resource.type in taggable_resources
	has_tag(resource, "Environment")
	env_value := resource.values.tags.Environment
	workspace_env := get_workspace_environment()
	workspace_env != "default"
	not env_matches_workspace(env_value, workspace_env)
	not has_exception(resource, "COMP-001")

	msg := sprintf(
		"资源 '%s' 环境标签 '%s' 与工作区环境 '%s' 不匹配",
		[resource.address, env_value, workspace_env],
	)
}

# 获取工作区对应的环境
get_workspace_environment := env if {
	workspace == "production"
	env := "prod"
} else := env if {
	workspace == "staging"
	env := "staging"
} else := env if {
	workspace == "development"
	env := "dev"
} else := workspace

# 检查环境标签是否与工作区匹配
env_matches_workspace(tag_env, workspace_env) if {
	tag_env == workspace_env
} else if {
	tag_env == "production"
	workspace_env == "prod"
} else if {
	tag_env == "development"
	workspace_env == "dev"
}

# 检查项目标签一致性
deny contains msg if {
	project_tags := {tag_value |
		resource := planned_resources[_]
		resource.type in taggable_resources
		has_tag(resource, "Project")
		tag_value := resource.values.tags.Project
	}
	count(project_tags) > 1

	msg := sprintf(
		"检测到多个不同的项目标签值: %v。所有资源应使用相同的项目标签。",
		[project_tags],
	)
}

# 检查Owner标签的邮箱域名
warn contains msg if {
	resource := planned_resources[_]
	resource.type in taggable_resources
	has_tag(resource, "Owner")
	owner_email := resource.values.tags.Owner
	not endswith(owner_email, "@company.com") # 假设公司域名

	msg := sprintf(
		"资源 '%s' Owner标签 '%s' 不是公司邮箱",
		[resource.address, owner_email],
	)
}

# 检查标签值长度
deny contains msg if {
	resource := planned_resources[_]
	resource.type in taggable_resources
	tag_name := {tag | resource.values.tags[tag]}[_]
	tag_value := resource.values.tags[tag_name]
	count(tag_value) > 256 # AWS标签值最大长度
	not has_exception(resource, "COMP-001")

	msg := sprintf(
		"资源 '%s' 标签 '%s' 值过长 (%d字符)，超过AWS限制 (256字符)",
		[resource.address, tag_name, count(tag_value)],
	)
}

# 检查标签数量限制
deny contains msg if {
	resource := planned_resources[_]
	resource.type in taggable_resources
	tag_count := count(resource.values.tags)
	tag_count > 50 # AWS最大标签数量
	not has_exception(resource, "COMP-001")

	msg := sprintf(
		"资源 '%s' 标签数量 %d 超过AWS限制 (50个)",
		[resource.address, tag_count],
	)
}

# 检查禁用的标签键
deny contains msg if {
	resource := planned_resources[_]
	resource.type in taggable_resources
	forbidden_tag := forbidden_tag_keys[_]
	has_tag(resource, forbidden_tag)
	not has_exception(resource, "COMP-001")

	msg := sprintf(
		"资源 '%s' 使用了禁用的标签键 '%s'",
		[resource.address, forbidden_tag],
	)
}

# 禁用的标签键
forbidden_tag_keys := [
	"aws:", # AWS保留前缀
	"Name", # 应使用资源名称而不是标签
	"name",
]

# 检查备份策略标签
warn contains msg if {
	resource := planned_resources[_]
	resource.type in backup_required_resources
	is_production(resource)
	not has_tag(resource, "BackupPolicy")

	msg := sprintf(
		"生产环境资源 '%s' 建议添加BackupPolicy标签以明确备份策略",
		[resource.address],
	)
}

# 需要备份策略的资源类型
backup_required_resources := {
	"aws_s3_bucket",
	"aws_ebs_volume",
	"aws_rds_instance",
	"aws_dynamodb_table",
}

# 检查自动化标签
warn contains msg if {
	count([resource |
		resource := planned_resources[_]
		resource.type in taggable_resources
		has_tag(resource, "CreatedBy")
		resource.values.tags.CreatedBy == "terraform"
	]) != count([resource |
		resource := planned_resources[_]
		resource.type in taggable_resources
	])

	msg := "存在未标记为terraform创建的资源，建议统一使用CreatedBy=terraform标签"
}

# 检查成本中心标签的有效性
deny contains msg if {
	resource := planned_resources[_]
	resource.type in taggable_resources
	has_tag(resource, "CostCenter")
	cost_center := resource.values.tags.CostCenter
	not cost_center in valid_cost_centers
	not has_exception(resource, "COMP-001")

	msg := sprintf(
		"资源 '%s' CostCenter标签值 '%s' 无效。有效值: %v",
		[resource.address, cost_center, valid_cost_centers],
	)
}

# 有效的成本中心列表（示例）
valid_cost_centers := {
	"CC-1001", # IT部门
	"CC-1002", # 研发部门
	"CC-1003", # 产品部门
	"CC-1004", # 运营部门
	"CC-1005", # 财务部门
}

# 检查标签继承 - 子资源应继承父资源标签
warn contains msg if {
	# Lambda函数的日志组应继承Lambda的标签
	lambda_resource := resources_by_type("aws_lambda_function")[_]
	lambda_name := lambda_resource.values.function_name
	log_group_name := sprintf("/aws/lambda/%s", [lambda_name])

	# 查找对应的日志组
	log_group := [lg |
		lg := resources_by_type("aws_cloudwatch_log_group")[_]
		lg.values.name == log_group_name
	][0]

	# 检查主要标签是否一致
	main_tags := ["Project", "Environment", "Owner"]
	missing_inherited_tags := [tag |
		tag := main_tags[_]
		has_tag(lambda_resource, tag)
		not has_tag(log_group, tag)
	]
	count(missing_inherited_tags) > 0

	msg := sprintf(
		"日志组 '%s' 应继承Lambda函数的标签: %v",
		[log_group.address, missing_inherited_tags],
	)
}
