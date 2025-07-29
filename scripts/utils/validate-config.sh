#!/bin/bash

# AWS RAG System Configuration Validator
# Version: 1.0
# Description: 配置文件验证工具

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 脚本目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# 验证结果
VALIDATION_PASSED=true
ERRORS=()
WARNINGS=()

# 打印消息
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# 记录错误
add_error() {
    ERRORS+=("$1")
    VALIDATION_PASSED=false
}

# 记录警告
add_warning() {
    WARNINGS+=("$1")
}

# 检查文件是否存在
check_file_exists() {
    local file=$1
    local required=$2
    
    if [ -f "$file" ]; then
        return 0
    else
        if [ "$required" = "required" ]; then
            add_error "必需的配置文件不存在: $file"
        else
            add_warning "可选的配置文件不存在: $file"
        fi
        return 1
    fi
}

# 验证YAML语法
validate_yaml_syntax() {
    local file=$1
    
    if ! command -v yq &> /dev/null; then
        add_warning "yq未安装，跳过YAML语法检查"
        return 0
    fi
    
    if yq eval '.' "$file" &> /dev/null; then
        print_message "$GREEN" "  ✓ YAML语法正确: $(basename "$file")"
    else
        add_error "YAML语法错误: $file"
        return 1
    fi
}

# 验证必需字段
validate_required_fields() {
    local file=$1
    local env=$2
    
    # 定义必需字段
    local required_fields=(
        "environment"
        "project.name"
        "aws.region"
        "lambda.runtime"
        "tags.Project"
        "tags.Environment"
    )
    
    for field in "${required_fields[@]}"; do
        if command -v yq &> /dev/null; then
            local value=$(yq eval ".$field" "$file" 2>/dev/null)
            if [ "$value" = "null" ] || [ -z "$value" ]; then
                add_error "缺少必需字段 '$field' 在 $file"
            fi
        fi
    done
}

# 验证环境变量引用
validate_env_vars() {
    local file=$1
    
    # 查找所有环境变量引用
    local env_vars=$(grep -oE '\$\{[A-Z_]+[A-Z0-9_]*\}' "$file" 2>/dev/null || true)
    
    if [ -n "$env_vars" ]; then
        print_message "$CYAN" "  检查环境变量引用..."
        while IFS= read -r var; do
            # 提取变量名
            local var_name=$(echo "$var" | sed 's/\${//;s/:.*//')
            var_name=${var_name%\}}
            
            # 检查是否有默认值
            if [[ "$var" == *":"* ]]; then
                print_message "$GREEN" "    • $var_name (有默认值)"
            else
                # 检查环境变量是否存在
                if [ -z "${!var_name}" ]; then
                    add_warning "环境变量 '$var_name' 未设置且无默认值"
                else
                    print_message "$GREEN" "    • $var_name = ${!var_name}"
                fi
            fi
        done <<< "$env_vars"
    fi
}

# 验证配置值范围
validate_config_values() {
    local file=$1
    local env=$2
    
    if ! command -v yq &> /dev/null; then
        return 0
    fi
    
    # Lambda内存大小检查
    local memory=$(yq eval '.lambda.memory_size' "$file" 2>/dev/null)
    if [ "$memory" != "null" ] && [ -n "$memory" ]; then
        if [ "$memory" -lt 128 ] || [ "$memory" -gt 10240 ]; then
            add_error "Lambda内存大小超出范围 (128-10240): $memory"
        fi
    fi
    
    # API Gateway限流检查
    local rate_limit=$(yq eval '.api_gateway.throttle_rate_limit' "$file" 2>/dev/null)
    if [ "$rate_limit" != "null" ] && [ -n "$rate_limit" ]; then
        if [ "$rate_limit" -lt 1 ] || [ "$rate_limit" -gt 10000000 ]; then
            add_warning "API Gateway速率限制可能不合理: $rate_limit"
        fi
    fi
    
    # 日志保留期检查
    local retention=$(yq eval '.monitoring.cloudwatch.retention_days' "$file" 2>/dev/null)
    if [ "$retention" != "null" ] && [ -n "$retention" ]; then
        local valid_days=(1 3 5 7 14 30 60 90 120 150 180 365 400 545 731 1827 3653)
        if [[ ! " ${valid_days[@]} " =~ " ${retention} " ]]; then
            add_error "CloudWatch日志保留期无效: $retention (必须是: ${valid_days[*]})"
        fi
    fi
}

# 验证安全配置
validate_security_config() {
    local file=$1
    local env=$2
    
    if ! command -v yq &> /dev/null; then
        return 0
    fi
    
    # 生产环境安全检查
    if [ "$env" = "prod" ]; then
        # 检查加密设置
        local encryption=$(yq eval '.s3.encryption' "$file" 2>/dev/null)
        if [ "$encryption" = "null" ] || [ "$encryption" != "aws:kms" ]; then
            add_warning "生产环境建议使用KMS加密"
        fi
        
        # 检查WAF
        local waf=$(yq eval '.security.enable_waf' "$file" 2>/dev/null)
        if [ "$waf" != "true" ]; then
            add_warning "生产环境建议启用WAF"
        fi
        
        # 检查SSL策略
        local ssl_policy=$(yq eval '.security.ssl_policy' "$file" 2>/dev/null)
        if [[ "$ssl_policy" != *"TLS-1-2"* ]]; then
            add_warning "建议使用TLS 1.2或更高版本"
        fi
    fi
}

# 验证单个环境配置
validate_environment() {
    local env=$1
    local config_file="$PROJECT_ROOT/environments/$env/config.yaml"
    
    print_message "$BLUE" "\n验证 $env 环境配置..."
    
    if check_file_exists "$config_file" "required"; then
        validate_yaml_syntax "$config_file"
        validate_required_fields "$config_file" "$env"
        validate_env_vars "$config_file"
        validate_config_values "$config_file" "$env"
        validate_security_config "$config_file" "$env"
    fi
}

# 验证基础配置
validate_base_config() {
    local base_file="$PROJECT_ROOT/environments/base.yaml"
    
    print_message "$BLUE" "验证基础配置模板..."
    
    if check_file_exists "$base_file" "required"; then
        validate_yaml_syntax "$base_file"
        validate_env_vars "$base_file"
    fi
}

# 检查配置继承
check_config_inheritance() {
    print_message "$BLUE" "\n检查配置继承关系..."
    
    for env in dev staging prod; do
        local config_file="$PROJECT_ROOT/environments/$env/config.yaml"
        if [ -f "$config_file" ]; then
            local extends=$(grep -E "^extends:" "$config_file" 2>/dev/null | cut -d' ' -f2 || echo "")
            if [ -n "$extends" ]; then
                print_message "$GREEN" "  ✓ $env 继承自: $extends"
            else
                add_warning "$env 环境未继承基础配置"
            fi
        fi
    done
}

# 生成验证报告
generate_report() {
    print_message "$BLUE" "\n======== 配置验证报告 ========"
    
    if [ ${#ERRORS[@]} -eq 0 ] && [ ${#WARNINGS[@]} -eq 0 ]; then
        print_message "$GREEN" "✅ 所有配置验证通过！"
        return 0
    fi
    
    if [ ${#ERRORS[@]} -gt 0 ]; then
        print_message "$RED" "\n错误 (${#ERRORS[@]}):"
        for error in "${ERRORS[@]}"; do
            echo "  ✗ $error"
        done
    fi
    
    if [ ${#WARNINGS[@]} -gt 0 ]; then
        print_message "$YELLOW" "\n警告 (${#WARNINGS[@]}):"
        for warning in "${WARNINGS[@]}"; do
            echo "  ⚠ $warning"
        done
    fi
    
    if [ "$VALIDATION_PASSED" = false ]; then
        print_message "$RED" "\n❌ 配置验证失败，请修复错误后重试。"
        return 1
    else
        print_message "$YELLOW" "\n⚠️  配置验证通过，但有警告需要注意。"
        return 0
    fi
}

# 主函数
main() {
    print_message "$BLUE" "========================================"
    print_message "$BLUE" "AWS RAG System 配置验证"
    print_message "$BLUE" "========================================"
    
    # 验证基础配置
    validate_base_config
    
    # 验证各环境配置
    if [ $# -eq 0 ]; then
        # 验证所有环境
        for env in dev staging prod; do
            validate_environment "$env"
        done
    else
        # 验证指定环境
        validate_environment "$1"
    fi
    
    # 检查继承关系
    check_config_inheritance
    
    # 生成报告
    generate_report
}

# 显示帮助
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: $0 [environment]"
    echo ""
    echo "验证AWS RAG System配置文件"
    echo ""
    echo "参数:"
    echo "  environment    要验证的环境 (dev|staging|prod)，不指定则验证所有环境"
    echo ""
    echo "示例:"
    echo "  $0           # 验证所有环境"
    echo "  $0 prod      # 只验证生产环境"
    exit 0
fi

# 执行主函数
main "$@"