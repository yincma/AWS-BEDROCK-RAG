package terraform.analysis

import future.keywords.contains
import future.keywords.if
import future.keywords.in

# S3 加密策略

__rego__metadoc__ := {
	"id": "SEC-001",
	"title": "S3存储桶加密要求",
	"description": "确保所有S3存储桶启用服务端加密",
	"severity": "HIGH",
	"category": "security",
	"controls": ["AWS-S3-001", "AWS-S3-002"],
}

# S3存储桶必须启用加密
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_s3_bucket"

	# 检查是否有豁免
	not has_exception(resource, "SEC-001")

	# 检查是否配置了服务端加密
	not resource.values.server_side_encryption_configuration

	msg := {
		"policy_id": "SEC-001",
		"resource": resource.address,
		"severity": "HIGH",
		"message": sprintf("S3存储桶 '%s' 必须启用服务端加密", [resource.address]),
		"remediation": "添加 server_side_encryption_configuration 块到 S3 存储桶配置中",
		"details": {
			"resource_type": resource.type,
			"resource_name": resource_name(resource),
			"current_config": "未配置加密",
		},
	}
}

# S3存储桶应使用KMS加密而非AES256
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_s3_bucket"

	not has_exception(resource, "SEC-002")

	# 存在加密配置但使用AES256
	encryption := resource.values.server_side_encryption_configuration[0].rule[0].apply_server_side_encryption_by_default
	encryption.sse_algorithm == "AES256"

	# 生产环境必须使用KMS
	is_production(resource)

	msg := {
		"policy_id": "SEC-002",
		"resource": resource.address,
		"severity": "MEDIUM",
		"message": sprintf("生产环境S3存储桶 '%s' 应使用KMS加密而非AES256", [resource.address]),
		"remediation": "将 sse_algorithm 设置为 'aws:kms' 并指定 KMS 密钥",
		"details": {
			"resource_type": resource.type,
			"current_algorithm": encryption.sse_algorithm,
			"recommended_algorithm": "aws:kms",
		},
	}
}

# S3存储桶公共访问阻止
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_s3_bucket_public_access_block"

	not has_exception(resource, "SEC-003")

	# 检查所有公共访问阻止设置
	settings := [
		resource.values.block_public_acls,
		resource.values.block_public_policy,
		resource.values.ignore_public_acls,
		resource.values.restrict_public_buckets,
	]

	# 至少有一个设置为false或未设置
	count([s | s := settings[_]; s != true]) > 0

	msg := {
		"policy_id": "SEC-003",
		"resource": resource.address,
		"severity": "HIGH",
		"message": sprintf("S3存储桶公共访问阻止 '%s' 必须启用所有阻止设置", [resource.address]),
		"remediation": "确保所有公共访问阻止设置都为 true",
		"details": {
			"resource_type": resource.type,
			"block_public_acls": resource.values.block_public_acls,
			"block_public_policy": resource.values.block_public_policy,
			"ignore_public_acls": resource.values.ignore_public_acls,
			"restrict_public_buckets": resource.values.restrict_public_buckets,
		},
	}
}

# Lambda函数加密策略

__lambda_encryption_metadoc__ := {
	"id": "SEC-010",
	"title": "Lambda函数加密要求",
	"description": "确保Lambda函数使用KMS加密环境变量",
	"severity": "MEDIUM",
	"category": "security",
	"controls": ["AWS-Lambda-001"],
}

# Lambda函数环境变量必须加密
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_lambda_function"

	not has_exception(resource, "SEC-010")

	# 存在环境变量但未加密
	resource.values.environment[0].variables
	count(resource.values.environment[0].variables) > 0
	not resource.values.kms_key_arn

	msg := {
		"policy_id": "SEC-010",
		"resource": resource.address,
		"severity": "MEDIUM",
		"message": sprintf("Lambda函数 '%s' 的环境变量必须使用KMS加密", [resource.address]),
		"remediation": "添加 kms_key_arn 参数以加密环境变量",
		"details": {
			"resource_type": resource.type,
			"function_name": resource.values.function_name,
			"environment_variables_count": count(resource.values.environment[0].variables),
			"encryption_status": "未加密",
		},
	}
}

# Lambda函数日志加密
deny contains msg if {
	# 查找Lambda函数
	lambda_resource := input.planned_values.root_module.resources[_]
	lambda_resource.type == "aws_lambda_function"

	not has_exception(lambda_resource, "SEC-011")

	# 查找对应的CloudWatch日志组
	log_group := input.planned_values.root_module.resources[_]
	log_group.type == "aws_cloudwatch_log_group"

	# 日志组名称应该匹配Lambda函数
	startswith(log_group.values.name, sprintf("/aws/lambda/%s", [lambda_resource.values.function_name]))

	# 检查日志组是否加密
	not log_group.values.kms_key_id

	msg := {
		"policy_id": "SEC-011",
		"resource": log_group.address,
		"severity": "MEDIUM",
		"message": sprintf("Lambda函数 '%s' 的CloudWatch日志组必须使用KMS加密", [lambda_resource.values.function_name]),
		"remediation": "为 CloudWatch 日志组添加 kms_key_id 参数",
		"details": {
			"lambda_function": lambda_resource.address,
			"log_group": log_group.address,
			"encryption_status": "未加密",
		},
	}
}

# EBS卷加密策略
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_ebs_volume"

	not has_exception(resource, "SEC-020")

	# EBS卷必须加密
	not resource.values.encrypted

	msg := {
		"policy_id": "SEC-020",
		"resource": resource.address,
		"severity": "HIGH",
		"message": sprintf("EBS卷 '%s' 必须启用加密", [resource.address]),
		"remediation": "设置 encrypted = true",
		"details": {
			"resource_type": resource.type,
			"volume_size": resource.values.size,
			"encryption_status": "未加密",
		},
	}
}

# RDS实例加密策略
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_db_instance"

	not has_exception(resource, "SEC-030")

	# RDS实例必须加密
	not resource.values.storage_encrypted

	msg := {
		"policy_id": "SEC-030",
		"resource": resource.address,
		"severity": "HIGH",
		"message": sprintf("RDS实例 '%s' 必须启用存储加密", [resource.address]),
		"remediation": "设置 storage_encrypted = true",
		"details": {
			"resource_type": resource.type,
			"engine": resource.values.engine,
			"instance_class": resource.values.instance_class,
			"encryption_status": "未加密",
		},
	}
}

# Secrets Manager密钥加密
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_secretsmanager_secret"

	not has_exception(resource, "SEC-040")

	# Secrets Manager密钥应使用客户管理的KMS密钥
	not resource.values.kms_key_id

	msg := {
		"policy_id": "SEC-040",
		"resource": resource.address,
		"severity": "MEDIUM",
		"message": sprintf("Secrets Manager密钥 '%s' 应使用客户管理的KMS密钥", [resource.address]),
		"remediation": "添加 kms_key_id 参数指定客户管理的KMS密钥",
		"details": {
			"resource_type": resource.type,
			"secret_name": resource.values.name,
			"encryption_type": "AWS管理的密钥",
		},
	}
}
