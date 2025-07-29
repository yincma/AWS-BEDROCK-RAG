package terraform.analysis

import future.keywords.contains
import future.keywords.if
import future.keywords.in

# 策略元数据
__rego__metadoc__ := {
	"id": "COST-002",
	"title": "成本预算策略",
	"description": "监控和控制基础设施成本，确保不超过预算限制",
	"severity": "HIGH",
	"category": "cost",
}

# 成本预算配置
budget_limits := {
	"monthly": {
		"dev": 500, # 开发环境月预算 $500
		"staging": 1000, # 预生产环境月预算 $1000
		"prod": 5000, # 生产环境月预算 $5000
	},
	"daily": {
		"dev": 20, # 开发环境日预算 $20
		"staging": 35, # 预生产环境日预算 $35
		"prod": 170, # 生产环境日预算 $170
	},
	"service_limits": {
		"opensearch_serverless": 1000, # OpenSearch Serverless月限额
		"bedrock_api": 800, # Bedrock API调用月限额
		"lambda_execution": 200, # Lambda执行月限额
		"s3_storage": 100, # S3存储月限额
		"cloudfront_transfer": 150, # CloudFront传输月限额
	},
}

# 服务成本率 (USD)
service_costs := {
	"aws_opensearch_serverless_collection": {
		"ocu_search_hour": 0.24, # 每OCU搜索小时
		"ocu_index_hour": 0.24, # 每OCU索引小时
	},
	"aws_lambda_function": {
		"request_million": 0.20, # 每百万请求
		"gb_second": 0.0000166667, # 每GB-秒
	},
	"aws_s3_bucket": {
		"standard_gb_month": 0.023, # 标准存储每GB每月
		"ia_gb_month": 0.0125, # 不频繁访问每GB每月
		"glacier_gb_month": 0.004, # Glacier每GB每月
	},
	"aws_cloudfront_distribution": {
		"request_10k": 0.0075, # 每万个请求
		"gb_transfer": 0.085, # 每GB传输
	},
	"aws_api_gateway_rest_api": {"request_million": 3.50}, # 每百万API调用
}

# 获取环境类型
get_environment(resource) := env if {
	env := lower(resource.values.tags.Environment)
} else := env if {
	env := lower(resource.values.tags.environment)
} else := env if {
	env := lower(resource.values.tags.Env)
} # 默认为开发环境

else := "dev"

# 计算Lambda函数预估月成本
calculate_lambda_cost(resource) := cost if {
	memory_mb := resource.values.memory_size
	timeout_sec := resource.values.timeout

	# 假设每月执行次数（基于环境）
	env := get_environment(resource)
	monthly_executions := monthly_execution_estimates[env]

	# 计算成本
	request_cost := (monthly_executions / 1000000) * service_costs.aws_lambda_function.request_million
	execution_cost := ((monthly_executions * (memory_mb / 1024)) * timeout_sec) * service_costs.aws_lambda_function.gb_second

	cost := request_cost + execution_cost
}

# 不同环境的月执行次数估算
monthly_execution_estimates := {
	"dev": 10000, # 开发环境1万次/月
	"staging": 50000, # 预生产5万次/月
	"prod": 500000, # 生产环境50万次/月
}

# 计算S3存储预估月成本
calculate_s3_cost(resource) := cost if {
	# 基于生命周期配置估算存储成本
	lifecycle := resource.values.lifecycle_configuration[_].rule[_]

	# 简化计算：假设100GB基础存储
	base_storage_gb := 100
	standard_cost := base_storage_gb * service_costs.aws_s3_bucket.standard_gb_month

	cost := standard_cost
} else := cost if {
	# 如果没有生命周期配置，使用默认估算
	cost := 100 * service_costs.aws_s3_bucket.standard_gb_month
}

# 计算OpenSearch Serverless预估月成本
calculate_opensearch_cost(resource) := cost if {
	# OpenSearch Serverless最小配置：2个OCU
	min_ocu := 2
	hours_per_month := 730

	search_cost := (min_ocu * hours_per_month) * service_costs.aws_opensearch_serverless_collection.ocu_search_hour
	index_cost := (min_ocu * hours_per_month) * service_costs.aws_opensearch_serverless_collection.ocu_index_hour

	cost := search_cost + index_cost
}

# 计算CloudFront预估月成本
calculate_cloudfront_cost(resource) := cost if {
	# 基于价格等级估算
	price_class := resource.values.price_class

	# 假设每月传输量和请求量（基于环境）
	env := get_environment(resource)
	monthly_gb := cloudfront_usage_estimates[env].gb_transfer
	monthly_requests := cloudfront_usage_estimates[env].requests

	transfer_cost := monthly_gb * service_costs.aws_cloudfront_distribution.gb_transfer
	request_cost := (monthly_requests / 10000) * service_costs.aws_cloudfront_distribution.request_10k

	cost := transfer_cost + request_cost
}

# CloudFront使用量估算
cloudfront_usage_estimates := {
	"dev": {"gb_transfer": 10, "requests": 100000}, # 开发环境
	"staging": {"gb_transfer": 50, "requests": 500000}, # 预生产环境
	"prod": {"gb_transfer": 500, "requests": 5000000}, # 生产环境
}

# 检查单个资源成本是否超限
deny contains msg if {
	resource := resources_by_type("aws_lambda_function")[_]
	cost := calculate_lambda_cost(resource)
	cost > 100 # 单个Lambda函数月成本超过$100
	not has_exception(resource, "COST-002")

	msg := sprintf(
		"Lambda函数 '%s' 预估月成本 $%.2f 过高。建议优化内存配置或执行频率。",
		[resource_name(resource), cost],
	)
}

deny contains msg if {
	resource := resources_by_type("aws_opensearch_serverless_collection")[_]
	cost := calculate_opensearch_cost(resource)
	cost > budget_limits.service_limits.opensearch_serverless
	not has_exception(resource, "COST-002")

	msg := sprintf(
		"OpenSearch Serverless集合 '%s' 预估月成本 $%.2f 超过限额 $%d。",
		[resource_name(resource), cost, budget_limits.service_limits.opensearch_serverless],
	)
}

# 检查环境总成本预算
deny contains msg if {
	env := {"dev", "staging", "prod"}[_]
	env_resources := [resource |
		resource := planned_resources[_]
		get_environment(resource) == env
	]

	total_cost := sum([estimated_cost(resource) | resource := env_resources[_]])
	limit := budget_limits.monthly[env]
	total_cost > limit

	msg := sprintf(
		"%s环境预估月成本 $%.2f 超过预算限额 $%d。请优化资源配置。",
		[env, total_cost, limit],
	)
}

# 检查是否缺少成本分配标签
deny contains msg if {
	resource := planned_resources[_]
	resource.type in aws_billable_resources
	not has_tag(resource, "CostCenter")
	not has_tag(resource, "Project")
	not has_exception(resource, "COST-002")

	msg := sprintf(
		"资源 '%s' 缺少成本分配标签 (CostCenter 或 Project)。这将影响成本追踪。",
		[resource.address],
	)
}

# 可计费的AWS资源类型
aws_billable_resources := {
	"aws_lambda_function",
	"aws_s3_bucket",
	"aws_opensearch_serverless_collection",
	"aws_cloudfront_distribution",
	"aws_api_gateway_rest_api",
	"aws_instance",
	"aws_ebs_volume",
	"aws_rds_instance",
}

# 成本告警 - 警告级别
warn contains msg if {
	resource := resources_by_type("aws_lambda_function")[_]
	cost := calculate_lambda_cost(resource)
	cost > 50 # 月成本超过$50时警告
	cost <= 100

	msg := sprintf(
		"Lambda函数 '%s' 预估月成本 $%.2f 较高，建议监控使用情况。",
		[resource_name(resource), cost],
	)
}

# 检查是否启用了成本优化功能
warn contains msg if {
	resource := resources_by_type("aws_s3_bucket")[_]
	not resource.values.lifecycle_configuration

	msg := sprintf(
		"S3存储桶 '%s' 未配置生命周期策略。建议配置以优化存储成本。",
		[resource_name(resource)],
	)
}

# 检查CloudFront是否使用了最优价格等级
warn contains msg if {
	resource := resources_by_type("aws_cloudfront_distribution")[_]
	price_class := resource.values.price_class
	price_class == "PriceClass_All"
	env := get_environment(resource)
	env != "prod" # 非生产环境不建议使用全球分发

	msg := sprintf(
		"CloudFront分发 '%s' 在%s环境使用全球价格等级。建议使用 PriceClass_100 或 PriceClass_200。",
		[resource_name(resource), env],
	)
}

# 检查是否配置了成本预算
deny contains msg if {
	count(resources_by_type("aws_budgets_budget")) == 0
	count(planned_resources) > 5 # 资源较多时必须配置预算

	msg := "项目包含多个可计费资源，但未配置AWS Budgets。建议设置成本预算和告警。"
}

# 检查生产环境的成本标签合规性
deny contains msg if {
	resource := planned_resources[_]
	is_production(resource)
	resource.type in aws_billable_resources
	not has_required_tags(resource, {"CostCenter", "Project", "Owner", "Environment"})
	not has_exception(resource, "COST-002")

	msg := sprintf(
		"生产环境资源 '%s' 缺少必需的成本管理标签。",
		[resource.address],
	)
}
