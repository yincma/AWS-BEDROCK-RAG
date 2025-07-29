package terraform.analysis

# 成本策略测试

# 测试Lambda内存限制策略
test_lambda_memory_limit_exceeded if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_lambda_function.high_memory",
		"type": "aws_lambda_function",
		"values": {
			"function_name": "test-function",
			"memory_size": 4096, # 超过限制
			"tags": {
				"Environment": "prod",
				"Project": "test",
			},
		},
	}]}}}

	violations := deny with input as test_input
	count(violations) > 0
	contains(violations[_], "内存配置")
}

test_lambda_memory_limit_within_bounds if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_lambda_function.normal_memory",
		"type": "aws_lambda_function",
		"values": {
			"function_name": "test-function",
			"memory_size": 1024, # 在限制内
			"tags": {
				"Environment": "prod",
				"Project": "test",
			},
		},
	}]}}}

	violations := deny with input as test_input
	not any_memory_violations(violations)
}

any_memory_violations(violations) if {
	some violation in violations
	contains(violation, "内存配置")
}

# 测试Lambda超时限制策略
test_lambda_timeout_limit_exceeded if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_lambda_function.long_timeout",
		"type": "aws_lambda_function",
		"values": {
			"function_name": "test-function",
			"timeout": 1200, # 超过限制
			"tags": {
				"Environment": "prod",
				"Project": "test",
			},
		},
	}]}}}

	violations := deny with input as test_input
	count(violations) > 0
	contains(violations[_], "超时配置")
}

# 测试豁免机制
test_lambda_memory_with_exception if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_lambda_function.exception_approved",
		"type": "aws_lambda_function",
		"values": {
			"function_name": "test-function",
			"memory_size": 4096, # 超过限制但有豁免
			"tags": {
				"Environment": "prod",
				"Project": "test",
				"opa-exception": "COST-001",
				"exception-expires": "2025-12-31",
			},
		},
	}]}}}

	violations := deny with input as test_input
	not any_memory_violations(violations) # 不应该有内存违规
}

# 测试CloudFront价格等级策略
test_cloudfront_price_class_all_denied if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_cloudfront_distribution.expensive",
		"type": "aws_cloudfront_distribution",
		"values": {
			"price_class": "PriceClass_All",
			"tags": {
				"Environment": "dev",
				"Project": "test",
			},
		},
	}]}}}

	violations := deny with input as test_input
	count(violations) > 0
	contains(violations[_], "全球价格等级")
}

# 测试成本分配标签
test_missing_cost_tags if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_lambda_function.no_cost_tags",
		"type": "aws_lambda_function",
		"values": {
			"function_name": "test-function",
			"memory_size": 512,
			"tags": {"Environment": "prod"},
			# 缺少Project和CostCenter标签

		},
	}]}}}

	violations := deny with input as test_input
	count(violations) > 0
	contains(violations[_], "成本分配标签")
}

# 测试生产环境成本标签合规性
test_production_cost_tags_compliance if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_opensearch_domain.prod_missing_tags",
		"type": "aws_opensearch_domain",
		"values": {
			"domain_name": "test-domain",
			"tags": {
				"Environment": "production",
				"Project": "test",
				# 缺少CostCenter和Owner
			},
		},
	}]}}}

	violations := deny with input as test_input
	count(violations) > 0
	contains(violations[_], "必需的成本管理标签")
}

# 测试S3生命周期策略建议
test_s3_lifecycle_warning if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_s3_bucket.no_lifecycle",
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
	contains(warnings[_], "生命周期策略")
}

# 测试成本计算函数
test_lambda_cost_calculation if {
	resource := {
		"type": "aws_lambda_function",
		"values": {
			"memory_size": 1024,
			"timeout": 30,
			"tags": {"Environment": "prod"},
		},
	}

	cost := calculate_lambda_cost(resource)
	cost > 0 # 应该计算出正数成本
	cost < 1000 # 不应该过高
}

# 测试环境预算检查
test_environment_budget_exceeded if {
	test_input := {"planned_values": {"root_module": {"resources": [
		{
			"address": "aws_lambda_function.expensive1",
			"type": "aws_lambda_function",
			"values": {
				"memory_size": 3008,
				"timeout": 900,
				"tags": {"Environment": "dev"},
			},
		},
		{
			"address": "aws_lambda_function.expensive2",
			"type": "aws_lambda_function",
			"values": {
				"memory_size": 3008,
				"timeout": 900,
				"tags": {"Environment": "dev"},
			},
		},
	]}}}

	violations := deny with input as test_input
	any_budget_violations(violations)
}

any_budget_violations(violations) if {
	some violation in violations
	contains(violation, "预算限额")
}

# 测试配置参数访问
test_cost_limit_retrieval if {
	dev_monthly := get_cost_limit("dev", "monthly")
	dev_monthly == 500

	prod_daily := get_cost_limit("prod", "daily")
	prod_daily == 170
}

# 测试豁免检查函数
test_exemption_validation if {
	resource_with_valid_exemption := {"values": {"tags": {
		"opa-exception": "COST-001",
		"exception-expires": "2025-12-31",
		"exception-reason": "business-critical-requirement",
	}}}

	is_exemption_valid(resource_with_valid_exemption, "COST-001")

	resource_with_invalid_exemption := {"values": {"tags": {
		"opa-exception": "COST-001",
		"exception-expires": "2024-01-01", # 已过期
		"exception-reason": "invalid-reason",
	}}}

	not is_exemption_valid(resource_with_invalid_exemption, "COST-001")
}
