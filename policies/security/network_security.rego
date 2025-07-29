package terraform.analysis

import future.keywords.contains
import future.keywords.if
import future.keywords.in

# 网络安全策略

__network_metadoc__ := {
	"id": "SEC-200",
	"title": "网络安全配置",
	"description": "确保网络资源遵循安全最佳实践",
	"severity": "HIGH",
	"category": "security",
	"controls": ["AWS-VPC-001", "AWS-SG-001", "AWS-NACL-001"],
}

# 安全组规则 - 禁止开放的入站规则
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_security_group"

	not has_exception(resource, "SEC-200")

	ingress := resource.values.ingress[_]

	# 检查是否有开放的CIDR（0.0.0.0/0）
	"0.0.0.0/0" in ingress.cidr_blocks

	# 检查是否是危险端口
	from_port := ingress.from_port
	to_port := ingress.to_port

	dangerous_ports := [22, 3389, 1433, 3306, 5432, 6379, 27017]
	port := dangerous_ports[_]

	from_port <= port
	to_port >= port

	msg := {
		"policy_id": "SEC-200",
		"resource": resource.address,
		"severity": "CRITICAL",
		"message": sprintf("安全组 '%s' 允许从互联网 (0.0.0.0/0) 访问危险端口 %d", [resource.address, port]),
		"remediation": "限制CIDR范围或使用特定的安全组作为来源",
		"details": {
			"resource_type": resource.type,
			"security_group_name": resource.values.name,
			"dangerous_port": port,
			"port_range": sprintf("%d-%d", [from_port, to_port]),
			"protocol": ingress.protocol,
		},
	}
}

# 安全组规则 - 禁止所有端口开放
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_security_group"

	not has_exception(resource, "SEC-201")

	ingress := resource.values.ingress[_]

	# 检查是否有开放所有端口的规则
	"0.0.0.0/0" in ingress.cidr_blocks
	ingress.from_port == 0
	ingress.to_port == 65535

	msg := {
		"policy_id": "SEC-201",
		"resource": resource.address,
		"severity": "CRITICAL",
		"message": sprintf("安全组 '%s' 允许从互联网访问所有端口 (0-65535)", [resource.address]),
		"remediation": "指定具体的端口范围和来源",
		"details": {
			"resource_type": resource.type,
			"security_group_name": resource.values.name,
			"protocol": ingress.protocol,
			"cidr_blocks": ingress.cidr_blocks,
		},
	}
}

# VPC流日志必须启用
deny contains msg if {
	# 查找VPC资源
	vpc_resource := input.planned_values.root_module.resources[_]
	vpc_resource.type == "aws_vpc"

	not has_exception(vpc_resource, "SEC-202")

	# 检查是否存在对应的流日志
	vpc_id := vpc_resource.values.id

	# 查找是否有流日志配置
	flow_logs := [log |
		log := input.planned_values.root_module.resources[_]
		log.type == "aws_flow_log"
		log.values.vpc_id == vpc_id
	]

	count(flow_logs) == 0

	msg := {
		"policy_id": "SEC-202",
		"resource": vpc_resource.address,
		"severity": "MEDIUM",
		"message": sprintf("VPC '%s' 必须启用流日志记录", [vpc_resource.address]),
		"remediation": "添加 aws_flow_log 资源以启用VPC流日志",
		"details": {
			"resource_type": vpc_resource.type,
			"vpc_cidr": vpc_resource.values.cidr_block,
			"flow_logs_count": count(flow_logs),
		},
	}
}

# 子网不应自动分配公共IP
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_subnet"

	not has_exception(resource, "SEC-203")

	# 公共子网除外，检查标签确定是否为私有子网
	not resource.values.tags.Type == "public"
	not resource.values.tags.type == "public"

	# 私有子网不应自动分配公共IP
	resource.values.map_public_ip_on_launch == true

	msg := {
		"policy_id": "SEC-203",
		"resource": resource.address,
		"severity": "MEDIUM",
		"message": sprintf("私有子网 '%s' 不应自动分配公共IP地址", [resource.address]),
		"remediation": "设置 map_public_ip_on_launch = false 或添加适当的标签",
		"details": {
			"resource_type": resource.type,
			"subnet_cidr": resource.values.cidr_block,
			"availability_zone": resource.values.availability_zone,
			"map_public_ip_on_launch": resource.values.map_public_ip_on_launch,
		},
	}
}

# NAT网关应在多个可用区
deny contains msg if {
	# 查找所有NAT网关
	nat_gateways := [nat |
		nat := input.planned_values.root_module.resources[_]
		nat.type == "aws_nat_gateway"
	]

	count(nat_gateways) > 0
	not has_exception(nat_gateways[0], "SEC-204")

	# 检查可用区多样性
	azs := {az |
		nat := nat_gateways[_]
		subnet := input.planned_values.root_module.resources[_]
		subnet.type == "aws_subnet"
		subnet.values.id == nat.values.subnet_id
		az := subnet.values.availability_zone
	}

	count(azs) < 2
	count(nat_gateways) >= 2

	msg := {
		"policy_id": "SEC-204",
		"resource": "NAT Gateways",
		"severity": "MEDIUM",
		"message": "NAT网关应部署在多个可用区以提高可用性",
		"remediation": "在不同的可用区创建NAT网关",
		"details": {
			"nat_gateway_count": count(nat_gateways),
			"availability_zones": azs,
			"recommendation": "至少在2个可用区部署NAT网关",
		},
	}
}

# 负载均衡器安全配置
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type in ["aws_lb", "aws_alb"]

	not has_exception(resource, "SEC-205")

	# 面向互联网的负载均衡器应启用访问日志
	resource.values.internal == false

	# 检查访问日志配置
	not resource.values.access_logs[0].enabled

	msg := {
		"policy_id": "SEC-205",
		"resource": resource.address,
		"severity": "MEDIUM",
		"message": sprintf("面向互联网的负载均衡器 '%s' 应启用访问日志", [resource.address]),
		"remediation": "在 access_logs 块中设置 enabled = true",
		"details": {
			"resource_type": resource.type,
			"load_balancer_name": resource.values.name,
			"internal": resource.values.internal,
			"scheme": resource.values.scheme,
		},
	}
}

# API Gateway应使用自定义域名和证书
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_api_gateway_rest_api"

	not has_exception(resource, "SEC-206")

	# 生产环境API应使用自定义域名
	is_production(resource)

	# 检查是否有对应的域名配置
	domain_names := [domain |
		domain := input.planned_values.root_module.resources[_]
		domain.type == "aws_api_gateway_domain_name"
		domain.values.rest_api_id == resource.values.id
	]

	count(domain_names) == 0

	msg := {
		"policy_id": "SEC-206",
		"resource": resource.address,
		"severity": "LOW",
		"message": sprintf("生产环境API Gateway '%s' 应使用自定义域名", [resource.address]),
		"remediation": "创建 aws_api_gateway_domain_name 资源并配置SSL证书",
		"details": {
			"resource_type": resource.type,
			"api_name": resource.values.name,
			"environment": resource.values.tags.Environment,
			"custom_domains_count": count(domain_names),
		},
	}
}

# CloudFront分发安全配置
deny contains msg if {
	resource := input.planned_values.root_module.resources[_]
	resource.type == "aws_cloudfront_distribution"

	not has_exception(resource, "SEC-207")

	# CloudFront应强制HTTPS
	default_cache := resource.values.default_cache_behavior[0]
	default_cache.viewer_protocol_policy in ["allow-all", "redirect-to-https"]
	default_cache.viewer_protocol_policy != "https-only"

	msg := {
		"policy_id": "SEC-207",
		"resource": resource.address,
		"severity": "MEDIUM",
		"message": sprintf("CloudFront分发 '%s' 应强制使用HTTPS", [resource.address]),
		"remediation": "设置 viewer_protocol_policy = 'https-only'",
		"details": {
			"resource_type": resource.type,
			"current_policy": default_cache.viewer_protocol_policy,
			"recommended_policy": "https-only",
		},
	}
}

# WAF规则应用于面向互联网的资源
deny contains msg if {
	# 查找面向互联网的ALB
	alb_resource := input.planned_values.root_module.resources[_]
	alb_resource.type in ["aws_lb", "aws_alb"]
	alb_resource.values.internal == false

	not has_exception(alb_resource, "SEC-208")

	# 检查是否有WAF关联
	waf_associations := [assoc |
		assoc := input.planned_values.root_module.resources[_]
		assoc.type == "aws_wafv2_web_acl_association"
		assoc.values.resource_arn == alb_resource.values.arn
	]

	count(waf_associations) == 0

	msg := {
		"policy_id": "SEC-208",
		"resource": alb_resource.address,
		"severity": "MEDIUM",
		"message": sprintf("面向互联网的负载均衡器 '%s' 应配置WAF保护", [alb_resource.address]),
		"remediation": "创建WAF Web ACL并关联到负载均衡器",
		"details": {
			"resource_type": alb_resource.type,
			"load_balancer_name": alb_resource.values.name,
			"waf_associations_count": count(waf_associations),
		},
	}
}
