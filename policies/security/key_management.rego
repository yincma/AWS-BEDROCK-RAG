package terraform.analysis

import future.keywords.contains
import future.keywords.if
import future.keywords.in

# 密钥管理策略

__kms_metadoc__ := {
	"id": "SEC-300",
	"title": "KMS密钥管理",
	"description": "确保KMS密钥遵循安全管理最佳实践",
	"severity": "HIGH",
	"category": "security",
	"controls": ["AWS-KMS-001", "AWS-KMS-002", "AWS-KMS-003"],
}

# KMS密钥必须启用密钥轮换
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_kms_key"

	not has_exception(resource, "SEC-300")

	# 检查是否启用了自动密钥轮换
	not resource.values.enable_key_rotation

	# 客户管理的密钥应该启用轮换
	resource.values.key_usage == "ENCRYPT_DECRYPT"

	msg := {
		"policy_id": "SEC-300",
		"resource": resource.address,
		"severity": "MEDIUM",
		"message": sprintf("KMS密钥 '%s' 应启用自动密钥轮换", [resource.address]),
		"remediation": "设置 enable_key_rotation = true",
		"details": {
			"resource_type": resource.type,
			"key_usage": resource.values.key_usage,
			"rotation_enabled": resource.values.enable_key_rotation,
			"description": resource.values.description,
		},
	}
}

# KMS密钥必须有适当的策略
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_kms_key"

	not has_exception(resource, "SEC-301")

	# 检查是否有密钥策略
	not resource.values.policy

	msg := {
		"policy_id": "SEC-301",
		"resource": resource.address,
		"severity": "HIGH",
		"message": sprintf("KMS密钥 '%s' 必须定义密钥策略", [resource.address]),
		"remediation": "添加明确的密钥策略以控制访问权限",
		"details": {
			"resource_type": resource.type,
			"description": resource.values.description,
			"policy_defined": false,
		},
	}
}

# KMS密钥策略不应允许过于宽泛的权限
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_kms_key"

	not has_exception(resource, "SEC-302")

	# 解析密钥策略
	resource.values.policy
	policy_doc := json.unmarshal(resource.values.policy)
	statement := policy_doc.Statement[_]

	statement.Effect == "Allow"

	# 检查是否有通配符Principal
	principal := statement.Principal
	principal == "*"

	# 检查是否没有限制条件
	not statement.Condition

	msg := {
		"policy_id": "SEC-302",
		"resource": resource.address,
		"severity": "HIGH",
		"message": sprintf("KMS密钥 '%s' 的策略允许任何主体访问且无条件限制", [resource.address]),
		"remediation": "限制Principal或添加Condition来控制访问",
		"details": {
			"resource_type": resource.type,
			"principal": principal,
			"actions": statement.Action,
			"has_conditions": false,
		},
	}
}

# KMS密钥别名应遵循命名约定
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_kms_alias"

	not has_exception(resource, "SEC-303")

	# 检查别名命名约定
	alias_name := resource.values.name

	# 别名应该包含环境和用途信息
	env_prefixes := ["dev-", "staging-", "prod-", "test-"]
	has_env := [prefix | prefix := env_prefixes[_]; startswith(alias_name, sprintf("alias/%s", [prefix]))]

	count(has_env) == 0

	msg := {
		"policy_id": "SEC-303",
		"resource": resource.address,
		"severity": "LOW",
		"message": sprintf("KMS别名 '%s' 应遵循命名约定 (alias/环境-用途)", [alias_name]),
		"remediation": "使用格式 'alias/环境-用途-描述' 的命名约定",
		"details": {
			"resource_type": resource.type,
			"current_name": alias_name,
			"expected_pattern": "alias/{env}-{purpose}-{description}",
		},
	}
}

# 密钥应有适当的标签
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_kms_key"

	not has_exception(resource, "SEC-304")

	# 检查必需的标签
	required_tags := ["Environment", "Purpose", "Owner"]
	missing_tags := [tag |
		tag := required_tags[_]
		not resource.values.tags[tag]
	]

	count(missing_tags) > 0

	msg := {
		"policy_id": "SEC-304",
		"resource": resource.address,
		"severity": "LOW",
		"message": sprintf("KMS密钥 '%s' 缺少必需标签: %s", [resource.address, missing_tags]),
		"remediation": sprintf("添加缺少的标签: %s", [missing_tags]),
		"details": {
			"resource_type": resource.type,
			"missing_tags": missing_tags,
			"current_tags": object.keys(resource.values.tags),
		},
	}
}

# 密钥删除保护
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_kms_key"

	not has_exception(resource, "SEC-305")

	# 生产环境密钥应启用删除保护
	is_production(resource)

	# 检查删除窗口期（7-30天）
	deletion_window := resource.values.deletion_window_in_days
	deletion_window < 30

	msg := {
		"policy_id": "SEC-305",
		"resource": resource.address,
		"severity": "MEDIUM",
		"message": sprintf("生产环境KMS密钥 '%s' 的删除窗口期应设置为最大值(30天)", [resource.address]),
		"remediation": "设置 deletion_window_in_days = 30",
		"details": {
			"resource_type": resource.type,
			"current_deletion_window": deletion_window,
			"recommended_deletion_window": 30,
			"environment": resource.values.tags.Environment,
		},
	}
}

# Secrets Manager应使用客户管理的KMS密钥
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_secretsmanager_secret"

	not has_exception(resource, "SEC-306")

	# 检查是否使用了客户管理的KMS密钥
	not resource.values.kms_key_id

	# 生产环境的密钥应使用客户管理的KMS
	is_production(resource)

	msg := {
		"policy_id": "SEC-306",
		"resource": resource.address,
		"severity": "MEDIUM",
		"message": sprintf("生产环境Secrets Manager密钥 '%s' 应使用客户管理的KMS密钥", [resource.address]),
		"remediation": "指定 kms_key_id 参数使用客户管理的KMS密钥",
		"details": {
			"resource_type": resource.type,
			"secret_name": resource.values.name,
			"kms_key_specified": false,
			"environment": resource.values.tags.Environment,
		},
	}
}

# RDS实例应使用客户管理的KMS密钥
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_db_instance"

	not has_exception(resource, "SEC-307")

	# 数据库已启用加密但使用默认密钥
	resource.values.storage_encrypted == true
	not resource.values.kms_key_id

	# 生产环境应使用客户管理的密钥
	is_production(resource)

	msg := {
		"policy_id": "SEC-307",
		"resource": resource.address,
		"severity": "MEDIUM",
		"message": sprintf("生产环境RDS实例 '%s' 应使用客户管理的KMS密钥进行加密", [resource.address]),
		"remediation": "指定 kms_key_id 参数使用客户管理的KMS密钥",
		"details": {
			"resource_type": resource.type,
			"db_instance_identifier": resource.values.identifier,
			"storage_encrypted": resource.values.storage_encrypted,
			"uses_customer_key": false,
		},
	}
}

# EBS卷应使用客户管理的KMS密钥
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_ebs_volume"

	not has_exception(resource, "SEC-308")

	# EBS卷已启用加密但使用默认密钥
	resource.values.encrypted == true
	not resource.values.kms_key_id

	# 敏感数据卷应使用客户管理的密钥
	sensitive_tags := ["sensitive", "confidential", "production"]
	has_sensitive_tag := [tag |
		tag := sensitive_tags[_]
		lower(resource.values.tags[tag]) in ["true", "yes", "1"]
	]
	count(has_sensitive_tag) > 0

	msg := {
		"policy_id": "SEC-308",
		"resource": resource.address,
		"severity": "MEDIUM",
		"message": sprintf("敏感EBS卷 '%s' 应使用客户管理的KMS密钥进行加密", [resource.address]),
		"remediation": "指定 kms_key_id 参数使用客户管理的KMS密钥",
		"details": {
			"resource_type": resource.type,
			"volume_size": resource.values.size,
			"encrypted": resource.values.encrypted,
			"sensitive_tags": has_sensitive_tag,
		},
	}
}
