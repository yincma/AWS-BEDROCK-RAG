package terraform.analysis

import future.keywords.contains
import future.keywords.if

# S3加密策略测试

test_s3_encryption_violation if {
	# 测试未加密的S3存储桶
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_s3_bucket.test_bucket",
		"type": "aws_s3_bucket",
		"values": {
			"bucket": "test-bucket-unencrypted",
			"tags": {"Environment": "test"},
		},
	}]}}}

	# 运行策略检查
	results := deny with input as test_input
	count(results) > 0

	# 验证结果包含S3加密错误
	result := results[_]
	result.policy_id == "SEC-001"
}

test_s3_encryption_compliance if {
	# 测试正确配置加密的S3存储桶
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_s3_bucket.test_bucket",
		"type": "aws_s3_bucket",
		"values": {
			"bucket": "test-bucket-encrypted",
			"server_side_encryption_configuration": [{"rule": [{"apply_server_side_encryption_by_default": {
				"sse_algorithm": "aws:kms",
				"kms_master_key_id": "alias/test-key",
			}}]}],
			"tags": {"Environment": "test"},
		},
	}]}}}

	# 运行策略检查
	results := deny with input as test_input

	# 验证没有加密相关的违规
	encryption_violations := [r | r := results[_]; r.policy_id in ["SEC-001", "SEC-002"]]
	count(encryption_violations) == 0
}

# 安全组测试

test_security_group_open_dangerous_port if {
	# 测试开放危险端口的安全组
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_security_group.test_sg",
		"type": "aws_security_group",
		"values": {
			"name": "test-sg-open",
			"ingress": [{
				"from_port": 22,
				"to_port": 22,
				"protocol": "tcp",
				"cidr_blocks": ["0.0.0.0/0"],
			}],
			"tags": {"Environment": "test"},
		},
	}]}}}

	# 运行策略检查
	results := deny with input as test_input
	count(results) > 0

	# 验证结果包含安全组错误
	result := results[_]
	result.policy_id == "SEC-200"
	contains(result.message, "危险端口")
}

test_security_group_restricted_access if {
	# 测试限制访问的安全组
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_security_group.test_sg",
		"type": "aws_security_group",
		"values": {
			"name": "test-sg-restricted",
			"ingress": [{
				"from_port": 22,
				"to_port": 22,
				"protocol": "tcp",
				"cidr_blocks": ["10.0.0.0/8"],
			}],
			"tags": {"Environment": "test"},
		},
	}]}}}

	# 运行策略检查
	results := deny with input as test_input

	# 验证没有安全组违规
	sg_violations := [r | r := results[_]; r.policy_id in ["SEC-200", "SEC-201"]]
	count(sg_violations) == 0
}

# IAM策略测试

test_iam_wildcard_violation if {
	# 测试包含通配符权限的IAM策略
	test_policy := {
		"Version": "2012-10-17",
		"Statement": [{
			"Effect": "Allow",
			"Action": "*",
			"Resource": "*",
		}],
	}

	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_iam_policy.test_policy",
		"type": "aws_iam_policy",
		"values": {
			"name": "test-wildcard-policy",
			"policy": json.marshal(test_policy),
			"tags": {"Environment": "test"},
		},
	}]}}}

	# 运行策略检查
	results := deny with input as test_input
	count(results) > 0

	# 验证结果包含IAM错误
	result := results[_]
	result.policy_id == "SEC-100"
	result.severity == "CRITICAL"
}

# KMS密钥测试

test_kms_key_rotation_violation if {
	# 测试未启用轮换的KMS密钥
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_kms_key.test_key",
		"type": "aws_kms_key",
		"values": {
			"description": "Test KMS key",
			"key_usage": "ENCRYPT_DECRYPT",
			"enable_key_rotation": false,
			"tags": {"Environment": "test"},
		},
	}]}}}

	# 运行策略检查
	results := deny with input as test_input
	count(results) > 0

	# 验证结果包含KMS轮换错误
	result := results[_]
	result.policy_id == "SEC-300"
}

# Lambda函数测试

test_lambda_environment_encryption if {
	# 测试Lambda函数环境变量加密
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_lambda_function.test_function",
		"type": "aws_lambda_function",
		"values": {
			"function_name": "test-function",
			"environment": [{"variables": {
				"DB_PASSWORD": "secret",
				"API_KEY": "api-secret",
			}}],
			"tags": {"Environment": "test"},
		},
	}]}}}

	# 运行策略检查
	results := deny with input as test_input
	count(results) > 0

	# 验证结果包含Lambda加密错误
	result := results[_]
	result.policy_id == "SEC-010"
}

# 豁免机制测试

test_policy_exemption if {
	# 测试策略豁免机制
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_s3_bucket.exempt_bucket",
		"type": "aws_s3_bucket",
		"values": {
			"bucket": "exempt-bucket",
			"tags": {
				"Environment": "test",
				"opa-exception": "SEC-001",
				"exception-reason": "临时测试桶",
				"exception-expires": "2025-12-31",
			},
		},
	}]}}}

	# 运行策略检查
	results := deny with input as test_input

	# 验证没有违规（由于豁免）
	s3_violations := [r | r := results[_]; r.policy_id == "SEC-001"]
	count(s3_violations) == 0
}

# 生产环境特殊要求测试

test_production_stricter_requirements if {
	# 测试生产环境更严格的要求
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_s3_bucket.prod_bucket",
		"type": "aws_s3_bucket",
		"values": {
			"bucket": "production-bucket",
			"server_side_encryption_configuration": [{"rule": [{"apply_server_side_encryption_by_default": {"sse_algorithm": "AES256"}}]}],
			"tags": {"Environment": "production"},
		},
	}]}}}

	# 运行策略检查
	results := deny with input as test_input
	count(results) > 0

	# 验证生产环境要求使用KMS
	result := results[_]
	result.policy_id == "SEC-002"
	contains(result.message, "生产环境")
	contains(result.message, "KMS")
}

# 网络安全测试

test_vpc_flow_logs_required if {
	# 测试VPC流日志要求
	test_input := {"planned_values": {"root_module": {"resources": [{
		"address": "aws_vpc.test_vpc",
		"type": "aws_vpc",
		"values": {
			"cidr_block": "10.0.0.0/16",
			"id": "vpc-12345",
			"tags": {"Environment": "test"},
		},
	}]}}}

	# 运行策略检查
	results := deny with input as test_input
	count(results) > 0

	# 验证VPC流日志要求
	result := results[_]
	result.policy_id == "SEC-202"
	contains(result.message, "流日志")
}
