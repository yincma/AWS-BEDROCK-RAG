package terraform.analysis

# 安全策略配置参数

# 当前AWS账户ID（应从环境变量或配置中获取）
current_account_id := "123456789012"

# 允许的AWS区域
allowed_regions := [
	"us-east-1",
	"us-west-2",
	"ap-northeast-1",
	"eu-west-1",
]

# 危险端口列表
dangerous_ports := [
	22, # SSH
	23, # Telnet
	135, # Windows RPC
	445, # SMB
	1433, # SQL Server
	1521, # Oracle
	3306, # MySQL
	3389, # RDP
	5432, # PostgreSQL
	5984, # CouchDB
	6379, # Redis
	7001, # Cassandra
	8086, # InfluxDB
	9042, # Cassandra
	9200, # Elasticsearch
	11211, # Memcached
	27017, # MongoDB
	50070, # Hadoop
]

# 危险的IAM权限
dangerous_iam_actions := [
	"iam:*",
	"iam:CreateRole",
	"iam:AttachRolePolicy",
	"iam:PutRolePolicy",
	"iam:CreateUser",
	"iam:AttachUserPolicy",
	"iam:PutUserPolicy",
	"ec2:TerminateInstances",
	"ec2:StopInstances",
	"rds:DeleteDBCluster",
	"rds:DeleteDBInstance",
	"s3:DeleteBucket",
	"s3:DeleteBucketPolicy",
	"cloudformation:DeleteStack",
	"lambda:DeleteFunction",
	"dynamodb:DeleteTable",
]

# 必需的资源标签
security_required_tags := [
	"Environment",
	"Project",
	"Owner",
	"CostCenter",
]

# 生产环境标识
production_environment_values := [
	"production",
	"prod",
	"live",
]

# 敏感数据标识
sensitive_data_tags := [
	"sensitive",
	"confidential",
	"restricted",
	"pii",
	"phi",
]

# KMS密钥删除窗口期配置
kms_deletion_window := {
	"minimum": 7,
	"recommended": 30,
	"production": 30,
}

# 加密算法配置
encryption_config := {
	"s3": {
		"allowed_algorithms": ["aws:kms", "AES256"],
		"production_required": "aws:kms",
	},
	"rds": {
		"required": true,
		"customer_managed_key_required": true,
	},
	"ebs": {
		"required": true,
		"customer_managed_key_for_sensitive": true,
	},
}

# 网络安全配置
network_security_config := {
	"vpc_flow_logs_required": true,
	"nat_gateway_multi_az_required": true,
	"waf_required_for_public_alb": true,
	"https_only_cloudfront": true,
}

# 访问控制配置
access_control_config := {
	"mfa_delete_required_for_production_s3": true,
	"api_gateway_authorization_required": true,
	"cross_account_access_requires_approval": true,
}

# 豁免标签配置
exemption_tag_key := "opa-exception"
exemption_reason_tag_key := "exception-reason"
exemption_expiry_tag_key := "exception-expires"

# 严重性级别映射
severity_mapping := {
	"CRITICAL": 4,
	"HIGH": 3,
	"MEDIUM": 2,
	"LOW": 1,
}

# 合规框架映射
compliance_frameworks := {
	"SOC2": ["SEC-001", "SEC-002", "SEC-100", "SEC-200", "SEC-300"],
	"PCI-DSS": ["SEC-001", "SEC-002", "SEC-003", "SEC-100", "SEC-200"],
	"HIPAA": ["SEC-001", "SEC-010", "SEC-030", "SEC-306", "SEC-307"],
	"ISO27001": ["SEC-001", "SEC-100", "SEC-200", "SEC-300"],
}

# 环境特定配置
security_environment_config := {
	"development": {
		"encryption_required": false,
		"customer_managed_keys_required": false,
		"vpc_flow_logs_required": false,
	},
	"staging": {
		"encryption_required": true,
		"customer_managed_keys_required": false,
		"vpc_flow_logs_required": true,
	},
	"production": {
		"encryption_required": true,
		"customer_managed_keys_required": true,
		"vpc_flow_logs_required": true,
		"mfa_delete_required": true,
		"waf_required": true,
	},
}

# 资源类型特定配置
resource_type_config := {
	"aws_s3_bucket": {
		"encryption_required": true,
		"public_access_block_required": true,
		"versioning_required_for_production": true,
	},
	"aws_lambda_function": {
		"environment_encryption_required": true,
		"vpc_required_for_production": false,
	},
	"aws_rds_db_instance": {
		"encryption_required": true,
		"backup_required": true,
		"multi_az_required_for_production": true,
	},
}
