package terraform.analysis

import future.keywords.contains
import future.keywords.if
import future.keywords.in

# 策略元数据
__rego__metadoc__ := {
	"id": "PERF-001",
	"title": "性能配置策略",
	"description": "确保AWS资源配置符合性能最佳实践，提供最优用户体验",
	"severity": "MEDIUM",
	"category": "performance",
}

# 性能配置基准
performance_benchmarks := {
	"lambda": {
		"min_memory_mb": 512, # 最小内存配置
		"recommended_memory_mb": 1024, # 推荐内存配置
		"max_timeout_seconds": 300, # 推荐最大超时
		"architecture": "arm64", # 推荐架构
	},
	"api_gateway": {
		"cache_enabled": true, # 是否启用缓存
		"cache_ttl_seconds": 300, # 缓存TTL
		"throttle_rate": 1000, # 限流速率
		"throttle_burst": 2000, # 突发限制
	},
	"cloudfront": {
		"min_ttl": 0, # 最小TTL
		"default_ttl": 86400, # 默认TTL (1天)
		"max_ttl": 31536000, # 最大TTL (1年)
		"compress": true, # 启用压缩
		"http2": true, # 启用HTTP/2
	},
	"s3": {
		"transfer_acceleration": true, # 传输加速
		"intelligent_tiering": true, # 智能分层
	},
	"opensearch": {
		"min_master_nodes": 3, # 最小主节点数
		"min_data_nodes": 2, # 最小数据节点数
		"ebs_throughput_mb": 125, # EBS吞吐量
		"dedicated_master": true, # 专用主节点
	},
}

# Lambda 性能配置检查
deny contains msg if {
	resource := resources_by_type("aws_lambda_function")[_]
	memory := resource.values.memory_size
	memory < performance_benchmarks.lambda.min_memory_mb
	is_production(resource)
	not has_exception(resource, "PERF-001")

	msg := sprintf(
		"生产环境Lambda函数 '%s' 内存配置 %dMB 低于推荐值 %dMB，可能影响性能。",
		[resource_name(resource), memory, performance_benchmarks.lambda.min_memory_mb],
	)
}

# Lambda 架构优化检查
warn contains msg if {
	resource := resources_by_type("aws_lambda_function")[_]
	architecture := resource.values.architectures[0]
	architecture != performance_benchmarks.lambda.architecture

	msg := sprintf(
		"Lambda函数 '%s' 使用 %s 架构。建议使用 %s 架构以获得更好的性价比。",
		[resource_name(resource), architecture, performance_benchmarks.lambda.architecture],
	)
}

# Lambda 超时配置检查
warn contains msg if {
	resource := resources_by_type("aws_lambda_function")[_]
	timeout := resource.values.timeout
	timeout > performance_benchmarks.lambda.max_timeout_seconds

	msg := sprintf(
		"Lambda函数 '%s' 超时配置 %d秒 过长，可能影响用户体验。建议优化代码或使用异步处理。",
		[resource_name(resource), timeout],
	)
}

# Lambda 预留并发配置检查
warn contains msg if {
	resource := resources_by_type("aws_lambda_function")[_]
	is_production(resource)
	not resource.values.reserved_concurrent_executions

	msg := sprintf(
		"生产环境Lambda函数 '%s' 未配置预留并发，可能在高负载时出现冷启动问题。",
		[resource_name(resource)],
	)
}

# API Gateway 缓存配置检查
warn contains msg if {
	resource := resources_by_type("aws_api_gateway_stage")[_]
	not resource.values.cache_cluster_enabled
	is_production(resource)

	msg := sprintf(
		"生产环境API Gateway阶段 '%s' 未启用缓存，可能影响响应性能。",
		[resource_name(resource)],
	)
}

# API Gateway 限流配置检查
deny contains msg if {
	resource := resources_by_type("aws_api_gateway_stage")[_]
	throttle := resource.values.throttle_settings[_]
	rate_limit := throttle.rate_limit
	rate_limit < 100 # 最小限流值
	not has_exception(resource, "PERF-001")

	msg := sprintf(
		"API Gateway阶段 '%s' 限流配置 %d 过低，可能影响正常用户访问。",
		[resource_name(resource), rate_limit],
	)
}

# CloudFront 缓存配置检查
warn contains msg if {
	resource := resources_by_type("aws_cloudfront_distribution")[_]
	behavior := resource.values.default_cache_behavior[_]
	not behavior.compress

	msg := sprintf(
		"CloudFront分发 '%s' 未启用压缩，将影响传输性能。",
		[resource_name(resource)],
	)
}

# CloudFront HTTP/2 支持检查
warn contains msg if {
	resource := resources_by_type("aws_cloudfront_distribution")[_]
	http_version := resource.values.http_version
	http_version != "http2"

	msg := sprintf(
		"CloudFront分发 '%s' 未启用HTTP/2，建议启用以提升性能。",
		[resource_name(resource)],
	)
}

# CloudFront 缓存TTL检查
warn contains msg if {
	resource := resources_by_type("aws_cloudfront_distribution")[_]
	behavior := resource.values.default_cache_behavior[_]
	default_ttl := behavior.default_ttl
	default_ttl < 3600 # 小于1小时

	msg := sprintf(
		"CloudFront分发 '%s' 默认TTL %d秒 过短，可能导致频繁回源。",
		[resource_name(resource), default_ttl],
	)
}

# S3 传输加速检查
warn contains msg if {
	resource := resources_by_type("aws_s3_bucket")[_]
	not resource.values.acceleration_status == "Enabled"
	is_production(resource)

	msg := sprintf(
		"生产环境S3存储桶 '%s' 未启用传输加速，可能影响文件上传性能。",
		[resource_name(resource)],
	)
}

# S3 智能分层检查
warn contains msg if {
	resource := resources_by_type("aws_s3_bucket")[_]
	not has_intelligent_tiering_config(resource)

	msg := sprintf(
		"S3存储桶 '%s' 未配置智能分层，可能导致存储成本过高。",
		[resource_name(resource)],
	)
}

# 检查S3是否配置了智能分层
has_intelligent_tiering_config(resource) if {
	resource.values.lifecycle_configuration[_].rule[_].transition[_].storage_class == "INTELLIGENT_TIERING"
} else if {
	# 检查是否有专门的智能分层配置资源
	bucket_name := resource.values.bucket
	some other_resource in planned_resources
	other_resource.type == "aws_s3_bucket_intelligent_tiering_configuration"
	other_resource.values.bucket == bucket_name
}

# OpenSearch 集群配置检查
deny contains msg if {
	resource := resources_by_type("aws_opensearch_domain")[_]
	cluster_config := resource.values.cluster_config[_]
	not cluster_config.dedicated_master_enabled
	is_production(resource)
	not has_exception(resource, "PERF-001")

	msg := sprintf(
		"生产环境OpenSearch域 '%s' 未启用专用主节点，可能影响集群稳定性。",
		[resource_name(resource)],
	)
}

# OpenSearch EBS 性能检查
warn contains msg if {
	resource := resources_by_type("aws_opensearch_domain")[_]
	ebs_options := resource.values.ebs_options[_]
	volume_type := ebs_options.volume_type
	volume_type == "standard" # 不推荐使用标准磁盘

	msg := sprintf(
		"OpenSearch域 '%s' 使用标准EBS卷，建议使用gp3或io1以提升性能。",
		[resource_name(resource)],
	)
}

# Lambda 层配置检查
warn contains msg if {
	resource := resources_by_type("aws_lambda_function")[_]
	not resource.values.layers
	code_size := resource.values.code_size
	code_size > 10485760 # 10MB

	msg := sprintf(
		"Lambda函数 '%s' 代码包较大 (%d字节) 但未使用层，可能影响冷启动性能。",
		[resource_name(resource), code_size],
	)
}

# VPC 端点配置检查
warn contains msg if {
	# 检查是否有Lambda函数在VPC中
	some lambda_resource in resources_by_type("aws_lambda_function")
	lambda_resource.values.vpc_config

	# 但没有配置VPC端点
	count(resources_by_type("aws_vpc_endpoint")) == 0

	msg := "Lambda函数在VPC中运行但未配置VPC端点，可能导致AWS服务访问延迟。"
}

# OpenSearch Serverless 性能配置
warn contains msg if {
	resource := resources_by_type("aws_opensearchserverless_collection")[_]
	is_production(resource)

	# 检查是否有适当的容量配置
	not has_capacity_policy_for_collection(resource)

	msg := sprintf(
		"生产环境OpenSearch Serverless集合 '%s' 建议配置容量策略以确保性能稳定。",
		[resource_name(resource)],
	)
}

# 检查是否为集合配置了容量策略
has_capacity_policy_for_collection(collection_resource) if {
	collection_name := collection_resource.values.name
	some policy_resource in planned_resources
	policy_resource.type == "aws_opensearchserverless_capacity_policy"
	policy_resource.values.policy_document_json
	contains(policy_resource.values.policy_document_json, collection_name)
}

# CloudWatch 日志保留期检查
warn contains msg if {
	resource := resources_by_type("aws_cloudwatch_log_group")[_]
	not resource.values.retention_in_days

	msg := sprintf(
		"CloudWatch日志组 '%s' 未设置保留期，可能导致存储成本过高。",
		[resource_name(resource)],
	)
}

# 网络性能优化检查
warn contains msg if {
	resource := resources_by_type("aws_instance")[_]
	instance_type := resource.values.instance_type
	not supports_enhanced_networking(instance_type)
	is_production(resource)

	msg := sprintf(
		"生产环境EC2实例 '%s' 类型 %s 不支持增强网络，可能影响网络性能。",
		[resource_name(resource), instance_type],
	)
}

# 检查实例类型是否支持增强网络
supports_enhanced_networking(instance_type) if {
	# 现代实例类型通常支持增强网络
	instance_families := {"t3", "t4g", "m5", "m6i", "c5", "c6i", "r5", "r6i"}
	family := substring(instance_type, 0, indexof(instance_type, "."))
	family in instance_families
}
