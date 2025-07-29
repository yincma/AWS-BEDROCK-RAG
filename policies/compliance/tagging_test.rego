package terraform.analysis

# 标签合规策略测试

# 测试缺少必需标签
test_missing_global_required_tags if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_lambda_function.missing_tags",
		"type": "aws_lambda_function",
		"values": {
			"function_name": "test-function",
			"tags": {"Project": "test"},
			# 缺少Environment, Owner, CreatedBy

		},
	}]}}}

	violations := deny with input as test_input
	count(violations) > 0
	contains(violations[_], "缺少必需标签")
}

# 测试生产环境额外标签要求
test_production_additional_tags if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_lambda_function.prod_missing_tags",
		"type": "aws_lambda_function",
		"values": {
			"function_name": "test-function",
			"tags": {
				"Project": "test",
				"Environment": "production",
				"Owner": "admin@company.com",
				"CreatedBy": "terraform",
				# 缺少CostCenter, BackupPolicy, MaintenanceWindow
			},
		},
	}]}}}

	violations := deny with input as test_input
	count(violations) > 0
	contains(violations[_], "生产环境资源")
	contains(violations[_], "缺少必需标签")
}

# 测试标签值格式验证
test_invalid_tag_format if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_lambda_function.invalid_tags",
		"type": "aws_lambda_function",
		"values": {
			"function_name": "test-function",
			"tags": {
				"Project": "TEST_PROJECT", # 不符合小写格式
				"Environment": "PROD", # 不符合预定义值
				"Owner": "invalid-email", # 不符合邮箱格式
				"CreatedBy": "manual",
				"CostCenter": "1234", # 不符合CC-前缀格式
			},
		},
	}]}}}

	violations := deny with input as test_input
	count(violations) >= 3 # 至少3个格式错误
}

# 测试有效的标签格式
test_valid_tag_format if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_lambda_function.valid_tags",
		"type": "aws_lambda_function",
		"values": {
			"function_name": "test-function",
			"tags": {
				"Project": "enterprise-rag",
				"Environment": "production",
				"Owner": "admin@company.com",
				"CreatedBy": "terraform",
				"CostCenter": "CC-1002",
				"BackupPolicy": "daily",
				"MaintenanceWindow": "sunday-2am",
			},
		},
	}]}}}

	violations := deny with input as test_input
	not any_format_violations(violations)
}

any_format_violations(violations) if {
	some violation in violations
	contains(violation, "格式要求")
}

# 测试环境标签与工作区一致性
test_environment_workspace_mismatch if {
	test_input := {
		"planned_values": {"root_module": {"resources": [{
			"address": "aws_lambda_function.env_mismatch",
			"type": "aws_lambda_function",
			"values": {
				"function_name": "test-function",
				"tags": {
					"Environment": "development", # 与production工作区不匹配
					"Project": "test",
					"Owner": "admin@company.com",
					"CreatedBy": "terraform",
				},
			},
		}]}},
		"workspace": "production",
	}

	violations := deny with input as test_input
	count(violations) > 0
	contains(violations[_], "不匹配")
}

# 测试项目标签一致性
test_inconsistent_project_tags if {
	test_input := {"planned_values": {"root_module": {"resources": [
		{
			"address": "aws_lambda_function.project1",
			"type": "aws_lambda_function",
			"values": {
				"function_name": "test-function-1",
				"tags": {
					"Project": "project-a",
					"Environment": "dev",
					"Owner": "admin@company.com",
					"CreatedBy": "terraform",
				},
			},
		},
		{
			"address": "aws_s3_bucket.project2",
			"type": "aws_s3_bucket",
			"values": {
				"bucket": "test-bucket",
				"tags": {
					"Project": "project-b", # 不同的项目标签
					"Environment": "dev",
					"Owner": "admin@company.com",
					"CreatedBy": "terraform",
				},
			},
		},
	]}}}

	violations := deny with input as test_input
	count(violations) > 0
	contains(violations[_], "多个不同的项目标签")
}

# 测试Owner邮箱域名警告
test_non_company_email_warning if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_lambda_function.external_owner",
		"type": "aws_lambda_function",
		"values": {
			"function_name": "test-function",
			"tags": {
				"Project": "test",
				"Environment": "dev",
				"Owner": "admin@external.com", # 非公司邮箱
				"CreatedBy": "terraform",
			},
		},
	}]}}}

	warnings := warn with input as test_input
	count(warnings) > 0
	contains(warnings[_], "不是公司邮箱")
}

# 测试标签值长度限制
test_tag_value_too_long if {
	long_value := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" # 300+字符
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_lambda_function.long_tag",
		"type": "aws_lambda_function",
		"values": {
			"function_name": "test-function",
			"tags": {
				"Project": "test",
				"Environment": "dev",
				"Owner": "admin@company.com",
				"CreatedBy": "terraform",
				"Description": long_value, # 超长值
			},
		},
	}]}}}

	violations := deny with input as test_input
	count(violations) > 0
	contains(violations[_], "值过长")
}

# 测试标签数量限制
test_too_many_tags if {
	# 创建超过50个标签的资源
	many_tags := object.union(
		{"Project": "test", "Environment": "dev", "Owner": "admin@company.com", "CreatedBy": "terraform"},
		{"tag1": "value", "tag2": "value", "tag3": "value", "tag4": "value", "tag5": "value", 
		 "tag6": "value", "tag7": "value", "tag8": "value", "tag9": "value", "tag10": "value",
		 "tag11": "value", "tag12": "value", "tag13": "value", "tag14": "value", "tag15": "value",
		 "tag16": "value", "tag17": "value", "tag18": "value", "tag19": "value", "tag20": "value",
		 "tag21": "value", "tag22": "value", "tag23": "value", "tag24": "value", "tag25": "value",
		 "tag26": "value", "tag27": "value", "tag28": "value", "tag29": "value", "tag30": "value",
		 "tag31": "value", "tag32": "value", "tag33": "value", "tag34": "value", "tag35": "value",
		 "tag36": "value", "tag37": "value", "tag38": "value", "tag39": "value", "tag40": "value",
		 "tag41": "value", "tag42": "value", "tag43": "value", "tag44": "value", "tag45": "value",
		 "tag46": "value", "tag47": "value", "tag48": "value", "tag49": "value", "tag50": "value"}
	)

	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_lambda_function.many_tags",
		"type": "aws_lambda_function",
		"values": {
			"function_name": "test-function",
			"tags": many_tags,
		},
	}]}}}

	violations := deny with input as test_input
	count(violations) > 0
	contains(violations[_], "超过AWS限制")
}

# 测试禁用标签键
test_forbidden_tag_keys if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_lambda_function.forbidden_tags",
		"type": "aws_lambda_function",
		"values": {
			"function_name": "test-function",
			"tags": {
				"Project": "test",
				"Environment": "dev",
				"Owner": "admin@company.com",
				"CreatedBy": "terraform",
				"aws:cloudformation:stack-name": "test", # 禁用的AWS前缀
				"Name": "test-function", # 禁用的Name标签
			},
		},
	}]}}}

	violations := deny with input as test_input
	count(violations) >= 2 # 至少2个禁用标签违规
}

# 测试备份策略标签建议
test_backup_policy_recommendation if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_s3_bucket.no_backup_policy",
		"type": "aws_s3_bucket",
		"values": {
			"bucket": "test-bucket",
			"tags": {
				"Project": "test",
				"Environment": "production",
				"Owner": "admin@company.com",
				"CreatedBy": "terraform",
				# 缺少BackupPolicy标签
			},
		},
	}]}}}

	warnings := warn with input as test_input
	count(warnings) > 0
	contains(warnings[_], "BackupPolicy标签")
}

# 测试自动化标签统一性
test_created_by_terraform_consistency if {
	test_input := {"planned_values": {"root_module": {"resources": [
		{
			"address": "aws_lambda_function.terraform_created",
			"type": "aws_lambda_function",
			"values": {
				"function_name": "test-function-1",
				"tags": {
					"Project": "test",
					"Environment": "dev",
					"Owner": "admin@company.com",
					"CreatedBy": "terraform",
				},
			},
		},
		{
			"address": "aws_s3_bucket.manual_created",
			"type": "aws_s3_bucket",
			"values": {
				"bucket": "test-bucket",
				"tags": {
					"Project": "test",
					"Environment": "dev",
					"Owner": "admin@company.com",
					"CreatedBy": "manual", # 不一致
				},
			},
		},
	]}}}

	warnings := warn with input as test_input
	count(warnings) > 0
	contains(warnings[_], "terraform创建")
}

# 测试成本中心标签有效性
test_invalid_cost_center if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_lambda_function.invalid_cost_center",
		"type": "aws_lambda_function",
		"values": {
			"function_name": "test-function",
			"tags": {
				"Project": "test",
				"Environment": "dev",
				"Owner": "admin@company.com",
				"CreatedBy": "terraform",
				"CostCenter": "CC-9999", # 无效的成本中心
			},
		},
	}]}}}

	violations := deny with input as test_input
	count(violations) > 0
	contains(violations[_], "CostCenter标签值")
	contains(violations[_], "无效")
}

# 测试标签继承
test_lambda_log_group_tag_inheritance if {
	test_input := {"planned_values": {"root_module": {"resources": [
		{
			"address": "aws_lambda_function.with_tags",
			"type": "aws_lambda_function",
			"values": {
				"function_name": "test-function",
				"tags": {
					"Project": "test",
					"Environment": "prod",
					"Owner": "admin@company.com",
					"CreatedBy": "terraform",
				},
			},
		},
		{
			"address": "aws_cloudwatch_log_group.missing_inherited_tags",
			"type": "aws_cloudwatch_log_group",
			"values": {
				"name": "/aws/lambda/test-function",
				"tags": {"CreatedBy": "terraform"},
				# 缺少从Lambda继承的标签

			},
		},
	]}}}

	warnings := warn with input as test_input
	count(warnings) > 0
	contains(warnings[_], "继承")
}

# 测试成本追踪标签
test_cost_tracking_tags_for_high_cost_resources if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_opensearch_domain.missing_cost_tags",
		"type": "aws_opensearch_domain",
		"values": {
			"domain_name": "test-domain",
			"tags": {
				"Environment": "prod",
				"Owner": "admin@company.com",
				# 缺少Project, CostCenter, BusinessUnit, Application
			},
		},
	}]}}}

	violations := deny with input as test_input
	count(violations) > 0
	contains(violations[_], "成本追踪标签")
}

# 测试豁免机制
test_tagging_exception if {
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_lambda_function.with_exception",
		"type": "aws_lambda_function",
		"values": {
			"function_name": "test-function",
			"tags": {
				"Project": "test",
				"opa-exception": "COMP-001",
				"exception-expires": "2025-12-31",
				# 缺少其他必需标签但有豁免
			},
		},
	}]}}}

	violations := deny with input as test_input
	not any_tag_violations(violations) # 有豁免，不应该有违规
}

any_tag_violations(violations) if {
	some violation in violations
	contains(violation, "缺少必需标签")
}
