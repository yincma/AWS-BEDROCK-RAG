package terraform.analysis

import future.keywords.contains
import future.keywords.if
import future.keywords.in

# IAM访问控制策略

__iam_metadoc__ := {
	"id": "SEC-100",
	"title": "IAM最小权限原则",
	"description": "确保IAM策略遵循最小权限原则",
	"severity": "HIGH",
	"category": "security",
	"controls": ["AWS-IAM-001", "AWS-IAM-002", "AWS-IAM-003"],
}

# 禁止使用通配符权限
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_iam_policy"

	not has_exception(resource, "SEC-100")

	# 解析策略文档
	policy_doc := json.unmarshal(resource.values.policy)
	statement := policy_doc.Statement[_]

	# 检查是否有通配符权限
	statement.Effect == "Allow"
	statement.Action == "*"
	statement.Resource == "*"

	msg := {
		"policy_id": "SEC-100",
		"resource": resource.address,
		"severity": "CRITICAL",
		"message": sprintf("IAM策略 '%s' 不能包含完全通配符权限 (Action:*, Resource:*)", [resource.address]),
		"remediation": "使用具体的Action和Resource，遵循最小权限原则",
		"details": {
			"resource_type": resource.type,
			"policy_name": resource.values.name,
			"violation": "Action和Resource都使用通配符",
		},
	}
}

# 禁止在策略中使用危险的管理员权限
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_iam_policy"

	not has_exception(resource, "SEC-101")

	policy_doc := json.unmarshal(resource.values.policy)
	statement := policy_doc.Statement[_]

	statement.Effect == "Allow"

	# 检查危险的权限
	dangerous_actions := [
		"iam:*",
		"iam:CreateRole",
		"iam:AttachRolePolicy",
		"iam:PutRolePolicy",
		"ec2:TerminateInstances",
		"rds:DeleteDBCluster",
		"rds:DeleteDBInstance",
		"s3:DeleteBucket",
	]

	action := statement.Action[_]
	action in dangerous_actions

	msg := {
		"policy_id": "SEC-101",
		"resource": resource.address,
		"severity": "HIGH",
		"message": sprintf("IAM策略 '%s' 包含危险权限 '%s'", [resource.address, action]),
		"remediation": "移除或限制危险权限的使用范围",
		"details": {
			"resource_type": resource.type,
			"policy_name": resource.values.name,
			"dangerous_action": action,
		},
	}
}

# Lambda执行角色最小权限检查
deny contains msg if {
	# 查找Lambda函数
	lambda_resource := input.planned_values.root_module.resources[_]
	lambda_resource.type == "aws_lambda_function"

	not has_exception(lambda_resource, "SEC-102")

	# 查找对应的IAM角色
	role_arn := lambda_resource.values.role
	role_name := split(role_arn, "/")[count(split(role_arn, "/")) - 1]

	# 查找角色策略
	policy_resource := input.planned_values.root_module.resources[_]
	policy_resource.type == "aws_iam_role_policy"
	policy_resource.values.role == role_name

	policy_doc := json.unmarshal(policy_resource.values.policy)
	statement := policy_doc.Statement[_]

	# 检查是否有过于宽泛的权限
	statement.Effect == "Allow"
	action := statement.Action[_]
	contains(action, "*")

	msg := {
		"policy_id": "SEC-102",
		"resource": policy_resource.address,
		"severity": "MEDIUM",
		"message": sprintf("Lambda函数 '%s' 的IAM角色包含过于宽泛的权限 '%s'", [lambda_resource.values.function_name, action]),
		"remediation": "为Lambda函数使用更具体的权限",
		"details": {
			"lambda_function": lambda_resource.address,
			"iam_policy": policy_resource.address,
			"broad_permission": action,
		},
	}
}

# S3存储桶策略安全检查
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_s3_bucket_policy"

	not has_exception(resource, "SEC-103")

	policy_doc := json.unmarshal(resource.values.policy)
	statement := policy_doc.Statement[_]

	# 检查是否允许公共读取
	statement.Effect == "Allow"
	principal := statement.Principal

	# 检查通配符Principal
	principal == "*"

	action := statement.Action[_]
	action in ["s3:GetObject", "s3:GetObjectVersion"]

	msg := {
		"policy_id": "SEC-103",
		"resource": resource.address,
		"severity": "HIGH",
		"message": sprintf("S3存储桶策略 '%s' 允许公共读取访问", [resource.address]),
		"remediation": "限制Principal或添加Condition来控制访问",
		"details": {
			"resource_type": resource.type,
			"bucket": resource.values.bucket,
			"public_action": action,
		},
	}
}

# 禁止跨账户访问（除非明确授权）
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type in ["aws_iam_policy", "aws_s3_bucket_policy"]

	not has_exception(resource, "SEC-104")

	# 获取当前账户ID（这里简化处理）
	current_account := "123456789012" # 应该从配置中获取

	policy_field := "policy"
	policy_doc := json.unmarshal(resource.values[policy_field])
	statement := policy_doc.Statement[_]

	statement.Effect == "Allow"

	# 检查Principal是否包含其他账户
	principal := statement.Principal.AWS[_]
	contains(principal, ":")
	account_id := split(principal, ":")[4]
	account_id != current_account

	# 检查是否有明确的跨账户访问标签
	not resource.values.tags["cross-account-approved"]

	msg := {
		"policy_id": "SEC-104",
		"resource": resource.address,
		"severity": "HIGH",
		"message": sprintf("策略 '%s' 包含未授权的跨账户访问 (账户: %s)", [resource.address, account_id]),
		"remediation": "添加标签 'cross-account-approved=true' 或移除跨账户权限",
		"details": {
			"resource_type": resource.type,
			"external_account": account_id,
			"current_account": current_account,
		},
	}
}

# API Gateway授权检查
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_api_gateway_method"

	not has_exception(resource, "SEC-105")

	# API Gateway方法应该有授权
	resource.values.authorization == "NONE"

	# 排除OPTIONS方法（CORS预检）
	resource.values.http_method != "OPTIONS"

	msg := {
		"policy_id": "SEC-105",
		"resource": resource.address,
		"severity": "MEDIUM",
		"message": sprintf("API Gateway方法 '%s %s' 缺少授权配置", [resource.values.http_method, resource.values.resource_id]),
		"remediation": "设置适当的authorization类型（AWS_IAM、COGNITO_USER_POOLS等）",
		"details": {
			"resource_type": resource.type,
			"http_method": resource.values.http_method,
			"current_authorization": resource.values.authorization,
		},
	}
}

# 确保使用MFA删除保护
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_s3_bucket"

	not has_exception(resource, "SEC-106")

	# 生产环境的关键存储桶应该有MFA删除保护
	is_production(resource)

	# 检查版本控制和MFA删除
	versioning := resource.values.versioning[0]
	not versioning.mfa_delete

	msg := {
		"policy_id": "SEC-106",
		"resource": resource.address,
		"severity": "MEDIUM",
		"message": sprintf("生产环境S3存储桶 '%s' 应启用MFA删除保护", [resource.address]),
		"remediation": "在版本控制配置中启用 mfa_delete = true",
		"details": {
			"resource_type": resource.type,
			"environment": resource.values.tags.Environment,
			"versioning_enabled": versioning.enabled,
			"mfa_delete": versioning.mfa_delete,
		},
	}
}
