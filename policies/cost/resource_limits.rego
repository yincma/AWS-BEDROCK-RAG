package terraform.analysis

import future.keywords.contains
import future.keywords.if
import future.keywords.in

# 策略元数据
__rego__metadoc__ := {
	"id": "COST-001",
	"title": "资源规模限制策略",
	"description": "限制资源规模以控制成本，防止意外创建过大的资源",
	"severity": "HIGH",
	"category": "cost",
}

# 配置参数
default_limits := {
	"lambda": {
		"memory_mb": 3008,
		"timeout_seconds": 900,
		"reserved_concurrency": 1000,
	},
	"s3": {
		"object_lock_days": 365,
		"lifecycle_days": 2555, # 7年
	},
	"opensearch": {
		"min_master_nodes": 3,
		"min_data_nodes": 2,
		"max_ebs_volume_size_gb": 1000,
	},
	"cloudfront": {"max_price_class": "PriceClass_200"},
	"api_gateway": {
		"throttle_burst_limit": 5000,
		"throttle_rate_limit": 2000,
	},
}

# Lambda 内存限制
deny contains msg if {
	resource := resources_by_type("aws_lambda_function")[_]
	memory := resource.values.memory_size
	memory > default_limits.lambda.memory_mb
	not has_exception(resource, "COST-001")

	msg := sprintf(
		"Lambda函数 '%s' 内存配置 %dMB 超过限制 %dMB。考虑优化代码或申请豁免。",
		[resource_name(resource), memory, default_limits.lambda.memory_mb],
	)
}

# Lambda 超时限制
deny contains msg if {
	resource := resources_by_type("aws_lambda_function")[_]
	timeout := resource.values.timeout
	timeout > default_limits.lambda.timeout_seconds
	not has_exception(resource, "COST-001")

	msg := sprintf(
		"Lambda函数 '%s' 超时配置 %d秒 超过限制 %d秒。长时间运行的任务建议使用其他服务。",
		[resource_name(resource), timeout, default_limits.lambda.timeout_seconds],
	)
}

# Lambda 预留并发限制
deny contains msg if {
	resource := resources_by_type("aws_lambda_function")[_]
	reserved_concurrency := resource.values.reserved_concurrent_executions
	reserved_concurrency > default_limits.lambda.reserved_concurrency
	not has_exception(resource, "COST-001")

	msg := sprintf(
		"Lambda函数 '%s' 预留并发 %d 超过限制 %d。高并发需求请联系架构师评估。",
		[resource_name(resource), reserved_concurrency, default_limits.lambda.reserved_concurrency],
	)
}

# S3 对象锁定期限制
deny contains msg if {
	resource := resources_by_type("aws_s3_bucket_object_lock_configuration")[_]
	lock_config := resource.values.rule[_].default_retention[_]
	days := lock_config.days
	days > default_limits.s3.object_lock_days
	not has_exception(resource, "COST-001")

	msg := sprintf(
		"S3存储桶对象锁定期 %d天 超过限制 %d天。长期保留需要业务审批。",
		[days, default_limits.s3.object_lock_days],
	)
}

# CloudFront 价格等级限制
deny contains msg if {
	resource := resources_by_type("aws_cloudfront_distribution")[_]
	price_class := resource.values.price_class
	price_class == "PriceClass_All"
	not has_exception(resource, "COST-001")

	msg := sprintf(
		"CloudFront分发 '%s' 使用全球价格等级。建议使用 %s 以降低成本。",
		[resource_name(resource), default_limits.cloudfront.max_price_class],
	)
}

# API Gateway 限流配置检查
deny contains msg if {
	resource := resources_by_type("aws_api_gateway_stage")[_]
	throttle := resource.values.throttle_settings[_]
	burst_limit := throttle.burst_limit
	burst_limit > default_limits.api_gateway.throttle_burst_limit
	not has_exception(resource, "COST-001")

	msg := sprintf(
		"API Gateway阶段 '%s' 突发限制 %d 超过推荐值 %d。高流量需求请评估成本影响。",
		[resource_name(resource), burst_limit, default_limits.api_gateway.throttle_burst_limit],
	)
}

# OpenSearch 实例规模检查
deny contains msg if {
	resource := resources_by_type("aws_opensearch_domain")[_]
	cluster_config := resource.values.cluster_config[_]
	master_count := cluster_config.master_instance_count
	master_count > default_limits.opensearch.min_master_nodes
	not has_exception(resource, "COST-001")

	msg := sprintf(
		"OpenSearch域 '%s' 主节点数量 %d 超过建议值。考虑优化集群配置以降低成本。",
		[resource_name(resource), master_count],
	)
}

# EBS 卷大小限制
deny contains msg if {
	resource := resources_by_type("aws_ebs_volume")[_]
	size := resource.values.size
	size > default_limits.opensearch.max_ebs_volume_size_gb
	not has_exception(resource, "COST-001")

	msg := sprintf(
		"EBS卷 '%s' 大小 %dGB 超过限制 %dGB。大容量存储建议使用S3等服务。",
		[resource_name(resource), size, default_limits.opensearch.max_ebs_volume_size_gb],
	)
}

# 检查是否配置了自动扩缩
warn contains msg if {
	resource := resources_by_type("aws_lambda_function")[_]
	not resource.values.reserved_concurrent_executions
	memory := resource.values.memory_size
	memory > 1024 # 大于1GB内存的函数建议配置并发控制

	msg := sprintf(
		"建议为大内存Lambda函数 '%s' (%dMB) 配置预留并发以避免成本超支。",
		[resource_name(resource), memory],
	)
}

# 多级别告警 - 警告级别
warn contains msg if {
	resource := resources_by_type("aws_lambda_function")[_]
	memory := resource.values.memory_size
	memory > default_limits.lambda.memory_mb * 0.8 # 80%阈值警告
	memory <= default_limits.lambda.memory_mb

	msg := sprintf(
		"Lambda函数 '%s' 内存配置 %dMB 接近限制值。建议监控使用情况。",
		[resource_name(resource), memory],
	)
}

# 检查生产环境资源配置
deny contains msg if {
	resource := resources_by_type("aws_lambda_function")[_]
	is_production(resource)
	memory := resource.values.memory_size
	memory < 512 # 生产环境最小内存要求
	not has_exception(resource, "COST-001")

	msg := sprintf(
		"生产环境Lambda函数 '%s' 内存配置 %dMB 过低，可能影响性能。建议至少512MB。",
		[resource_name(resource), memory],
	)
}
