#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_debug() {
    if [[ "${DEBUG}" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
    fi
}

# 环境验证
validate_environment() {
    local env=$1
    if [[ ! "$env" =~ ^(dev|staging|prod)$ ]]; then
        log_error "无效的环境: $env"
        log_info "有效的环境: dev, staging, prod"
        exit 1
    fi
}

# 加载环境配置
load_environment_config() {
    local env=$1
    local config_file="config/environments/${env}.env"
    
    if [[ -f "$config_file" ]]; then
        source "$config_file"
        log_info "已加载环境配置: $config_file"
    else
        log_warn "环境配置文件不存在: $config_file"
    fi
    
    # 设置环境变量
    export ENVIRONMENT="${env}"
    export AWS_REGION="${AWS_REGION:-us-east-1}"
}

# AWS配置检查
check_aws_credentials() {
    if ! aws sts get-caller-identity &>/dev/null; then
        log_error "AWS凭证未配置或无效"
        log_info "请运行: aws configure"
        exit 1
    fi
    
    local identity=$(aws sts get-caller-identity --query 'Arn' --output text)
    log_info "AWS身份: $identity"
}

# 检查必需的工具
check_required_tools() {
    local tools=("aws" "terraform" "node" "npm" "python3" "pip3" "jq")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "缺少必需的工具: ${missing_tools[*]}"
        exit 1
    fi
    
    log_info "所有必需的工具已安装"
}

# 获取项目根目录
get_project_root() {
    local current_dir="$PWD"
    while [[ "$current_dir" != "/" ]]; do
        if [[ -f "$current_dir/project.yaml" ]] || [[ -d "$current_dir/.git" ]]; then
            echo "$current_dir"
            return
        fi
        current_dir=$(dirname "$current_dir")
    done
    echo "$PWD"
}

# 确认操作
confirm_action() {
    local message="${1:-继续操作？}"
    local default="${2:-n}"
    
    if [[ "$default" == "y" ]]; then
        local prompt="$message [Y/n]: "
        local default_value="y"
    else
        local prompt="$message [y/N]: "
        local default_value="n"
    fi
    
    read -p "$prompt" -n 1 -r
    echo
    
    if [[ -z "$REPLY" ]]; then
        REPLY="$default_value"
    fi
    
    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        return 1
    fi
    
    return 0
}

# 获取Terraform输出
get_terraform_output() {
    local output_name=$1
    local env=${2:-$ENVIRONMENT}
    local terraform_dir="infrastructure/terraform"
    
    cd "$terraform_dir" || exit 1
    terraform output -raw "$output_name" 2>/dev/null || echo ""
    cd - >/dev/null || exit 1
}

# 等待资源就绪
wait_for_resource() {
    local resource_type=$1
    local resource_id=$2
    local max_wait=${3:-300}  # 默认5分钟
    local interval=10
    local elapsed=0
    
    log_info "等待 $resource_type ($resource_id) 就绪..."
    
    while [[ $elapsed -lt $max_wait ]]; do
        case "$resource_type" in
            "lambda")
                if aws lambda get-function --function-name "$resource_id" &>/dev/null; then
                    log_success "$resource_type 已就绪"
                    return 0
                fi
                ;;
            "api-gateway")
                if aws apigateway get-rest-api --rest-api-id "$resource_id" &>/dev/null; then
                    log_success "$resource_type 已就绪"
                    return 0
                fi
                ;;
            "cloudfront")
                local status=$(aws cloudfront get-distribution --id "$resource_id" --query 'Distribution.Status' --output text 2>/dev/null)
                if [[ "$status" == "Deployed" ]]; then
                    log_success "$resource_type 已就绪"
                    return 0
                fi
                ;;
            *)
                log_error "未知的资源类型: $resource_type"
                return 1
                ;;
        esac
        
        sleep $interval
        elapsed=$((elapsed + interval))
        echo -n "."
    done
    
    echo
    log_error "等待超时: $resource_type ($resource_id)"
    return 1
}

# 创建备份
create_backup() {
    local backup_name="${1:-backup}"
    local backup_dir="backups/$(date '+%Y%m%d_%H%M%S')_${backup_name}"
    
    mkdir -p "$backup_dir"
    
    # 备份Terraform状态
    if [[ -f "infrastructure/terraform/terraform.tfstate" ]]; then
        cp infrastructure/terraform/terraform.tfstate "$backup_dir/"
        log_info "已备份Terraform状态"
    fi
    
    # 备份配置文件
    if [[ -d "config" ]]; then
        cp -r config "$backup_dir/"
        log_info "已备份配置文件"
    fi
    
    log_success "备份完成: $backup_dir"
}

# 清理临时文件
cleanup_temp_files() {
    local temp_dirs=(".terraform" "node_modules" "__pycache__" ".pytest_cache" "*.pyc" "*.pyo")
    
    for pattern in "${temp_dirs[@]}"; do
        find . -type d -name "$pattern" -exec rm -rf {} + 2>/dev/null || true
        find . -type f -name "$pattern" -exec rm -f {} + 2>/dev/null || true
    done
    
    log_info "已清理临时文件"
}

# 导出函数
export -f log_info log_warn log_error log_success log_debug
export -f validate_environment load_environment_config
export -f check_aws_credentials check_required_tools
export -f get_project_root confirm_action
export -f get_terraform_output wait_for_resource
export -f create_backup cleanup_temp_files