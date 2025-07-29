package terraform.analysis

# 性能策略测试

# 测试生产环境Lambda内存配置
test_production_lambda_low_memory if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_lambda_function.low_memory_prod",
		"type": "aws_lambda_function",
		"values": {
			"function_name": "test-function",
			"memory_size": 256, # 低于推荐值
			"tags": {
				"Environment": "production",
				"Project": "test",
			},
		},
	}]}}}

	violations := deny with input as test_input
	count(violations) > 0
	contains(violations[_], "低于推荐值")
}

# 测试Lambda架构建议
test_lambda_architecture_recommendation if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_lambda_function.x86_arch",
		"type": "aws_lambda_function",
		"values": {
			"function_name": "test-function",
			"architectures": ["x86_64"],
			"tags": {
				"Environment": "prod",
				"Project": "test",
			},
		},
	}]}}}

	warnings := warn with input as test_input
	count(warnings) > 0
	contains(warnings[_], "arm64 架构")
}

# 测试Lambda超时配置
test_lambda_long_timeout_warning if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_lambda_function.long_timeout",
		"type": "aws_lambda_function",
		"values": {
			"function_name": "test-function",
			"timeout": 600, # 超过推荐值
			"tags": {
				"Environment": "prod",
				"Project": "test",
			},
		},
	}]}}}

	warnings := warn with input as test_input
	count(warnings) > 0
	contains(warnings[_], "过长")
}

# 测试生产环境Lambda预留并发
test_production_lambda_no_reserved_concurrency if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_lambda_function.no_reserved_concurrency",
		"type": "aws_lambda_function",
		"values": {
			"function_name": "test-function",
			"memory_size": 1024,
			"tags": {
				"Environment": "production",
				"Project": "test",
			},
			# 没有reserved_concurrent_executions
		},
	}]}}}

	warnings := warn with input as test_input
	count(warnings) > 0
	contains(warnings[_], "预留并发")
}

# 测试API Gateway缓存配置
test_api_gateway_no_cache_in_production if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_api_gateway_stage.no_cache",
		"type": "aws_api_gateway_stage",
		"values": {
			"stage_name": "prod",
			"cache_cluster_enabled": false,
			"tags": {
				"Environment": "production",
				"Project": "test",
			},
		},
	}]}}}

	warnings := warn with input as test_input
	count(warnings) > 0
	contains(warnings[_], "未启用缓存")
}

# 测试API Gateway限流配置
test_api_gateway_low_throttle_limit if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_api_gateway_stage.low_throttle",
		"type": "aws_api_gateway_stage",
		"values": {
			"stage_name": "prod",
			"throttle_settings": [{"rate_limit": 50}], # 低于最小值
			"tags": {
				"Environment": "production",
				"Project": "test",
			},
		},
	}]}}}

	violations := deny with input as test_input
	count(violations) > 0
	contains(violations[_], "限流配置")
}

# 测试CloudFront压缩配置
test_cloudfront_no_compression if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_cloudfront_distribution.no_compression",
		"type": "aws_cloudfront_distribution",
		"values": {
			"default_cache_behavior": [{"compress": false}],
			"tags": {
				"Environment": "prod",
				"Project": "test",
			},
		},
	}]}}}

	warnings := warn with input as test_input
	count(warnings) > 0
	contains(warnings[_], "未启用压缩")
}

# 测试CloudFront HTTP版本
test_cloudfront_http_version if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_cloudfront_distribution.http1",
		"type": "aws_cloudfront_distribution",
		"values": {
			"http_version": "http1.1",
			"tags": {
				"Environment": "prod",
				"Project": "test",
			},
		},
	}]}}}

	warnings := warn with input as test_input
	count(warnings) > 0
	contains(warnings[_], "HTTP/2")
}

# 测试CloudFront缓存TTL
test_cloudfront_short_ttl if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_cloudfront_distribution.short_ttl",
		"type": "aws_cloudfront_distribution",
		"values": {
			"default_cache_behavior": [{"default_ttl": 1800}], # 30分钟，小于1小时
			"tags": {
				"Environment": "prod",
				"Project": "test",
			},
		},
	}]}}}

	warnings := warn with input as test_input
	count(warnings) > 0
	contains(warnings[_], "过短")
}

# 测试S3传输加速
test_s3_no_transfer_acceleration_in_production if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_s3_bucket.no_acceleration",
		"type": "aws_s3_bucket",
		"values": {
			"bucket": "test-bucket",
			"acceleration_status": "Suspended",
			"tags": {
				"Environment": "production",
				"Project": "test",
			},
		},
	}]}}}

	warnings := warn with input as test_input
	count(warnings) > 0
	contains(warnings[_], "传输加速")
}

# 测试S3智能分层配置
test_s3_no_intelligent_tiering if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_s3_bucket.no_intelligent_tiering",
		"type": "aws_s3_bucket",
		"values": {
			"bucket": "test-bucket",
			"tags": {
				"Environment": "prod",
				"Project": "test",
			},
			# 没有lifecycle_configuration
		},
	}]}}}

	warnings := warn with input as test_input
	count(warnings) > 0
	contains(warnings[_], "智能分层")
}

# 测试OpenSearch专用主节点
test_opensearch_no_dedicated_master_in_production if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_opensearch_domain.no_dedicated_master",
		"type": "aws_opensearch_domain",
		"values": {
			"domain_name": "test-domain",
			"cluster_config": [{"dedicated_master_enabled": false}],
			"tags": {
				"Environment": "production",
				"Project": "test",
			},
		},
	}]}}}

	violations := deny with input as test_input
	count(violations) > 0
	contains(violations[_], "专用主节点")
}

# 测试OpenSearch EBS卷类型
test_opensearch_standard_ebs_volume if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_opensearch_domain.standard_ebs",
		"type": "aws_opensearch_domain",
		"values": {
			"domain_name": "test-domain",
			"ebs_options": [{"volume_type": "standard"}],
			"tags": {
				"Environment": "prod",
				"Project": "test",
			},
		},
	}]}}}

	warnings := warn with input as test_input
	count(warnings) > 0
	contains(warnings[_], "gp3或io1")
}

# 测试Lambda层使用建议
test_lambda_large_code_no_layers if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_lambda_function.large_code",
		"type": "aws_lambda_function",
		"values": {
			"function_name": "test-function",
			"code_size": 15000000, # 15MB，大于10MB
			"tags": {
				"Environment": "prod",
				"Project": "test",
			},
			# 没有layers配置
		},
	}]}}}

	warnings := warn with input as test_input
	count(warnings) > 0
	contains(warnings[_], "冷启动性能")
}

# 测试VPC端点建议
test_lambda_in_vpc_no_endpoints if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_lambda_function.in_vpc",
		"type": "aws_lambda_function",
		"values": {
			"function_name": "test-function",
			"vpc_config": {
				"subnet_ids": ["subnet-123"],
				"security_group_ids": ["sg-123"],
			},
			"tags": {
				"Environment": "prod",
				"Project": "test",
			},
		},
	}]}}}

	# 没有aws_vpc_endpoint资源

	warnings := warn with input as test_input
	count(warnings) > 0
	contains(warnings[_], "VPC端点")
}

# 测试OpenSearch Serverless容量策略
test_opensearch_serverless_no_capacity_policy if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_opensearchserverless_collection.no_capacity_policy",
		"type": "aws_opensearchserverless_collection",
		"values": {
			"name": "test-collection",
			"tags": {
				"Environment": "production",
				"Project": "test",
			},
		},
	}]}}}

	warnings := warn with input as test_input
	count(warnings) > 0
	contains(warnings[_], "容量策略")
}

# 测试CloudWatch日志保留期
test_cloudwatch_log_group_no_retention if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_cloudwatch_log_group.no_retention",
		"type": "aws_cloudwatch_log_group",
		"values": {
			"name": "/aws/lambda/test-function",
			"tags": {
				"Environment": "prod",
				"Project": "test",
			},
			# 没有retention_in_days
		},
	}]}}}

	warnings := warn with input as test_input
	count(warnings) > 0
	contains(warnings[_], "保留期")
}

# 测试增强网络支持
test_instance_no_enhanced_networking if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_instance.old_type",
		"type": "aws_instance",
		"values": {
			"instance_type": "t2.small", # 不支持增强网络
			"tags": {
				"Environment": "production",
				"Project": "test",
			},
		},
	}]}}}

	warnings := warn with input as test_input
	count(warnings) > 0
	contains(warnings[_], "增强网络")
}

# 测试辅助函数
test_supports_enhanced_networking_function if {
	# 测试现代实例类型
	supports_enhanced_networking("t3.medium")
	supports_enhanced_networking("m5.large")
	supports_enhanced_networking("c6i.xlarge")

	# 测试旧实例类型（应该返回false或undefined）
	not supports_enhanced_networking("t1.micro")
}

# 测试是否正确识别生产环境
test_is_production_function if {
	prod_resource := {"values": {"tags": {"Environment": "production"}}}
	is_production(prod_resource)

	dev_resource := {"values": {"tags": {"Environment": "dev"}}}
	not is_production(dev_resource)
}
