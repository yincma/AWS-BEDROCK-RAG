package terraform.analysis

import future.keywords.contains
import future.keywords.if
import future.keywords.in

# 通用辅助函数

# 获取所有计划创建的资源
planned_resources := input.planned_values.root_module.resources

# 获取所有计划创建的特定类型资源
resources_by_type(resource_type) := resources if {
	resources := [resource |
		resource := planned_resources[_]
		resource.type == resource_type
	]
}

# 检查资源是否有特定标签
has_tag(resource, tag_key) if {
	resource.values.tags[tag_key]
}

# 检查资源是否有所有必需的标签
has_required_tags(resource, required_tags) if {
	missing_tags := required_tags - {tag | resource.values.tags[tag]}
	count(missing_tags) == 0
}

# 获取资源的名称
resource_name(resource) := name if {
	name := resource.values.name
} else := name if {
	name := resource.values.bucket
} else := name if {
	name := resource.values.function_name
} else := name if {
	name := resource.address
}

# 检查字符串是否匹配模式
matches_pattern(str, pattern) if {
	regex.match(pattern, str)
}

# 获取资源的区域
resource_region(resource) := region if {
	region := resource.values.region
} else := region if {
	region := input.configuration.provider_config.aws.expressions.region.constant_value
} else := "us-east-1"

# 检查资源是否在允许的区域
in_allowed_regions(resource, allowed_regions) if {
	resource_region(resource) in allowed_regions
}

# 计算资源的估算成本（简化版本）
estimated_cost(resource) := cost if {
	# Lambda 函数成本估算
	resource.type == "aws_lambda_function"
	memory := resource.values.memory_size
	cost := (memory * 0.0000166667) * 100000 # 假设每月10万次调用
} else := cost if {
	# S3 存储桶成本估算
	resource.type == "aws_s3_bucket"
	cost := 0.023 * 100 # 假设100GB存储
} else := cost if {
	# EC2 实例成本估算
	resource.type == "aws_instance"
	instance_type := resource.values.instance_type
	cost := instance_costs[instance_type]
} else := 0

# EC2 实例类型成本映射（每月估算）
instance_costs := {
	"t2.micro": 8.5,
	"t2.small": 17,
	"t2.medium": 34,
	"t3.micro": 7.5,
	"t3.small": 15,
	"t3.medium": 30,
	"m5.large": 70,
	"m5.xlarge": 140,
	"m5.2xlarge": 280,
}

# 严重性级别
severity_levels := {
	"LOW": 1,
	"MEDIUM": 2,
	"HIGH": 3,
	"CRITICAL": 4,
}

# 检查是否有豁免
has_exception(resource, policy_id) if {
	resource.values.tags["opa-exception"] == policy_id
	expiry := resource.values.tags["exception-expires"]

	# 简化的日期比较（实际应该解析日期）
	expiry > "2025-01-01"
}

# 获取资源的所有者
resource_owner(resource) := owner if {
	owner := resource.values.tags.Owner
} else := owner if {
	owner := resource.values.tags.owner
} else := "unknown"

# 检查是否是生产环境
is_production(resource) if {
	env := resource.values.tags.Environment
	lower(env) == "production"
} else if {
	env := resource.values.tags.environment
	lower(env) == "production"
} else if {
	env := resource.values.tags.Env
	lower(env) == "prod"
}

# 获取资源的项目名称
resource_project(resource) := project if {
	project := resource.values.tags.Project
} else := project if {
	project := resource.values.tags.project
} else := "unknown"
