package terraform.analysis

import future.keywords.contains
import future.keywords.if

# Terraform 特定的辅助函数

# 获取 Terraform 版本
terraform_version := version if {
	version := input.terraform_version
}

# 检查 Terraform 版本是否满足要求
terraform_version_valid if {
	semver.compare(terraform_version, ">=1.0.0") >= 0
}

# 获取所有提供商配置
provider_configs[provider] if {
	provider := input.configuration.provider_config[_]
}

# 获取 AWS 提供商配置
aws_provider_config := config if {
	config := input.configuration.provider_config.aws
}

# 获取默认 AWS 区域
default_aws_region := region if {
	region := aws_provider_config.expressions.region.constant_value
} else := "us-east-1"

# 获取所有模块
modules[module] if {
	module := input.configuration.root_module.module_calls[_]
}

# 获取变量值
variable_value(name) := value if {
	value := input.variables[name].value
}

# 获取输出值
output_value(name) := value if {
	value := input.outputs[name].value
}

# 检查是否使用了特定的 Terraform 功能
uses_feature(feature) if {
	feature == "count"
	some resource in planned_resources
	resource.count_index
} else if {
	feature == "for_each"
	some resource in planned_resources
	resource.for_each_key
} else if {
	feature == "dynamic"

	# 检查动态块的使用比较复杂，这里简化处理
	contains(input.configuration_string, "dynamic")
}

# 获取资源的依赖关系
resource_dependencies(resource) := deps if {
	deps := resource.depends_on
} else := []

# 检查是否有循环依赖（简化版本）
has_circular_dependency if {
	some resource in planned_resources
	deps := resource_dependencies(resource)
	resource.address in deps
}

# 获取资源的提供商
resource_provider(resource) := provider if {
	provider := resource.provider_config_key
} else := "aws"

# 检查是否使用了数据源
uses_data_source(type) if {
	some resource in input.configuration.root_module.resources
	resource.type == type
	startswith(resource.type, "data.")
}

# 获取后端配置
backend_type := type if {
	type := input.configuration.terraform.backend.type
} else := "local"

# 检查是否使用远程后端
uses_remote_backend if {
	backend_type != "local"
}

# 检查是否启用了后端加密
backend_encrypted if {
	backend_type == "s3"
	input.configuration.terraform.backend.config.encrypt == true
} else if {
	backend_type == "azurerm"

	# Azure 后端默认加密
	true
} else if {
	backend_type == "gcs"

	# GCS 后端默认加密
	true
}

# 获取工作区名称
workspace := name if {
	name := input.workspace
} else := "default"

# 检查是否在生产工作区
is_production_workspace if {
	workspace in ["production", "prod", "main"]
}

# 获取资源的生命周期规则
resource_lifecycle(resource) := lifecycle if {
	lifecycle := resource.lifecycle
} else := {}

# 检查资源是否设置为防止销毁
prevent_destroy(resource) if {
	lifecycle := resource_lifecycle(resource)
	lifecycle.prevent_destroy == true
}

# 检查是否使用了敏感变量
has_sensitive_variables if {
	some var in input.variables
	input.variables[var].sensitive == true
}

# 获取模块源
module_source(module_name) := source if {
	source := input.configuration.root_module.module_calls[module_name].source
}

# 检查是否使用了本地模块
uses_local_module(module_name) if {
	source := module_source(module_name)
	startswith(source, "./")
} else if {
	source := module_source(module_name)
	startswith(source, "../")
}

# 检查是否使用了远程模块
uses_remote_module(module_name) if {
	not uses_local_module(module_name)
}
