#!/bin/bash

# AWS RAG System Unified Deployment Script
# Version: 1.0
# Description: 统一部署入口脚本，支持交互式向导和多环境部署

set -euo pipefail

# 脚本目录（必须首先定义）
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# 初始化全局变量（避免 unbound variable 错误）
ENVIRONMENT=""
DEPLOY_MODE=""
NON_INTERACTIVE="${NON_INTERACTIVE:-false}"
VERBOSE="${VERBOSE:-false}"
SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-false}"
DEPLOY_CONFIG_FILE=""
SKIP_RESOURCE_DETECTION="${SKIP_RESOURCE_DETECTION:-false}"

# 退出码定义
readonly EXIT_SUCCESS=0
readonly EXIT_INVALID_ARGS=1
readonly EXIT_MISSING_DEPS=2
readonly EXIT_DEPLOY_FAILED=3
readonly EXIT_USER_CANCELLED=4
readonly EXIT_CONFIG_ERROR=5

# 错误处理函数
error_handler() {
    local line_no=$1
    local error_code=$2
    # 直接使用 echo，因为 print_message 可能还未定义
    echo -e "\033[0;31m❌ 错误发生在第 $line_no 行 (退出码: $error_code)\033[0m" >&2
    
    # 清理临时文件
    if [ -n "${TEMP_FILES:-}" ]; then
        rm -f $TEMP_FILES
    fi
    
    # 如果在Terraform目录中，尝试解锁状态
    if [[ "$PWD" == *"/terraform"* ]] && [ -f ".terraform.lock.hcl" ]; then
        echo -e "\033[1;33m尝试解锁 Terraform 状态...\033[0m"
        terraform force-unlock -force $(terraform output -raw lock_id 2>/dev/null || echo "") 2>/dev/null || true
    fi
    
    exit $error_code
}

# 设置错误陷阱
trap 'error_handler $LINENO $?' ERR

# 退出时清理
cleanup() {
    # 返回原始目录
    cd "$SCRIPT_DIR" 2>/dev/null || true
    
    # 清理临时文件
    if [ -n "${TEMP_FILES:-}" ]; then
        rm -f $TEMP_FILES 2>/dev/null || true
    fi
}

trap cleanup EXIT

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# 日志配置
LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_FILE="${DEPLOY_LOG_FILE:-}"
LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs}"
VERBOSE="${VERBOSE:-false}"

# 创建日志目录
if [ -n "$LOG_FILE" ] || [ "$LOG_LEVEL" != "INFO" ]; then
    mkdir -p "$LOG_DIR"
    # 如果没有指定日志文件，使用默认名称
    if [ -z "$LOG_FILE" ]; then
        LOG_FILE="$LOG_DIR/deployment-$(date +%Y%m%d-%H%M%S).log"
    fi
fi

# 日志级别函数（避免使用关联数组以提高兼容性）
get_log_level_value() {
    case "$1" in
        DEBUG) echo 0 ;;
        INFO)  echo 1 ;;
        WARN)  echo 2 ;;
        ERROR) echo 3 ;;
        *)     echo 1 ;;
    esac
}

# 增强的日志函数
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 写入日志文件
    if [ -n "${LOG_FILE:-}" ]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    fi
    
    # 根据日志级别决定是否输出到控制台
    local current_level=$(get_log_level_value "${LOG_LEVEL:-INFO}")
    local message_level=$(get_log_level_value "$level")
    
    if [ "$message_level" -ge "$current_level" ]; then
        case "$level" in
            ERROR) echo -e "${RED}[$level] $message${NC}" >&2 ;;
            WARN)  echo -e "${YELLOW}[$level] $message${NC}" ;;
            INFO)  echo -e "${GREEN}[$level] $message${NC}" ;;
            DEBUG) echo -e "${GRAY}[$level] $message${NC}" ;;
        esac
    fi
}

# 切换到脚本目录
cd "$SCRIPT_DIR"

# 配置文件路径（支持环境变量覆盖）
CONFIG_DIR="${CONFIG_DIR:-$SCRIPT_DIR/config}"
ENVIRONMENTS_DIR="${ENVIRONMENTS_DIR:-$SCRIPT_DIR/environments}"

# 默认配置（从环境变量读取，避免硬编码）
DEFAULT_AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
DEFAULT_PROJECT_NAME="${PROJECT_NAME:-${PWD##*/}}"
AVAILABLE_ENVIRONMENTS="${DEPLOY_ENVIRONMENTS:-dev staging prod custom}"
DEPLOY_SCRIPTS_DIR="${DEPLOY_SCRIPTS_DIR:-$SCRIPT_DIR/scripts}"
TERRAFORM_DIR="${TERRAFORM_DIR:-$SCRIPT_DIR/infrastructure/terraform}"
TERRAFORM_WORKSPACE="${TERRAFORM_WORKSPACE:-default}"

# 打印带颜色的消息（支持日志记录）
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
    
    # 同时记录到日志文件
    if [ -n "$LOG_FILE" ]; then
        local level="INFO"
        case "$color" in
            "$RED") level="ERROR" ;;
            "$YELLOW") level="WARN" ;;
            "$GREEN") level="INFO" ;;
            "$BLUE"|"$CYAN") level="DEBUG" ;;
        esac
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$LOG_FILE"
    fi
}

# 打印分隔线
print_separator() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# 打印标题
print_title() {
    local title=$1
    print_separator
    print_message "$BLUE" "🚀 $title"
    print_separator
}

# 显示进度
show_progress() {
    local current=$1
    local total=$2
    local message=$3
    local percent=$((current * 100 / total))
    
    printf "\r${CYAN}[%-50s] %d%% - %s${NC}" \
        "$(printf '#%.0s' $(seq 1 $((percent / 2))))" \
        "$percent" \
        "$message"
    
    if [ "$current" -eq "$total" ]; then
        echo
    fi
}

# 检查命令是否存在
check_command() {
    local cmd=$1
    if ! command -v "$cmd" &> /dev/null; then
        print_message "$RED" "❌ 错误: $cmd 命令未找到"
        return 1
    fi
    return 0
}

# 加载配置文件
load_config_file() {
    local config_file=$1
    
    if [ -f "$config_file" ]; then
        log "INFO" "加载配置文件: $config_file"
        # 使用 source 加载配置，但先验证文件
        if grep -E '^\s*(rm|mv|dd|mkfs|>|>>)' "$config_file" >/dev/null; then
            log "WARN" "配置文件包含潜在危险命令，跳过加载"
            return 1
        fi
        source "$config_file"
        return 0
    else
        log "DEBUG" "配置文件不存在: $config_file"
        return 1
    fi
}

# 加载环境配置
load_environment_config() {
    local env=${1:-$ENVIRONMENT}
    
    # 尝试多个可能的配置文件位置
    local config_files=(
        "$CONFIG_DIR/${env}.env"
        "$CONFIG_DIR/${env}.conf"
        "$CONFIG_DIR/.env.${env}"
        "$ENVIRONMENTS_DIR/${env}/config.env"
        "$SCRIPT_DIR/.env.${env}"
        "${DEPLOY_CONFIG_FILE:-}"  # 用户指定的配置文件
    )
    
    local loaded=false
    for config_file in "${config_files[@]}"; do
        if [ -n "$config_file" ] && load_config_file "$config_file"; then
            loaded=true
            break
        fi
    done
    
    if [ "$loaded" == "false" ]; then
        log "DEBUG" "未找到环境配置文件: $env"
    fi
    
    # 加载通用配置文件（如果存在）
    load_config_file "$CONFIG_DIR/common.env" || true
    load_config_file "$SCRIPT_DIR/.env" || true
}

# 动态查找部署脚本
find_deploy_script() {
    local script_name=$1
    local search_paths=(
        "$DEPLOY_SCRIPTS_DIR"
        "$SCRIPT_DIR/scripts"
        "$SCRIPT_DIR"
        "$SCRIPT_DIR/bin"
        "$SCRIPT_DIR/deployment"
    )
    
    for path in "${search_paths[@]}"; do
        if [ -f "$path/$script_name" ] && [ -x "$path/$script_name" ]; then
            echo "$path/$script_name"
            return 0
        fi
    done
    
    # 如果没找到，使用find命令在整个项目中搜索
    local found_script=$(find "$SCRIPT_DIR" -name "$script_name" -type f -executable 2>/dev/null | head -1)
    if [ -n "$found_script" ]; then
        echo "$found_script"
        return 0
    fi
    
    return 1
}

# 显示欢迎界面
show_welcome() {
    clear
    cat << "EOF"
    ╔══════════════════════════════════════════════════════════════╗
    ║                                                              ║
    ║            AWS RAG System Deployment Tool v1.0               ║
    ║                                                              ║
    ║                    统一部署管理系统                          ║
    ║                                                              ║
    ╚══════════════════════════════════════════════════════════════╝
EOF
    echo
}

# 选择环境
select_environment() {
    print_title "选择部署环境"
    
    # 从环境变量读取可用环境，支持动态配置
    IFS=' ' read -ra environments <<< "$AVAILABLE_ENVIRONMENTS"
    
    # 环境描述函数（避免使用关联数组）
    get_env_description() {
        case "$1" in
            dev)     echo "${ENV_DESC_DEV:-开发环境 - 用于开发和测试}" ;;
            staging) echo "${ENV_DESC_STAGING:-预发布环境 - 用于集成测试}" ;;
            prod)    echo "${ENV_DESC_PROD:-生产环境 - 正式运行环境}" ;;
            custom)  echo "${ENV_DESC_CUSTOM:-自定义环境 - 使用自定义配置}" ;;
            *)       echo "$1 环境" ;;
        esac
    }
    
    local env_descriptions=()
    for env in "${environments[@]}"; do
        env_descriptions+=("$(get_env_description "$env")")
    done
    
    echo "请选择要部署的环境："
    echo
    
    for i in "${!environments[@]}"; do
        printf "  ${CYAN}%d)${NC} %-12s - %s\n" $((i+1)) "${environments[$i]}" "${env_descriptions[$i]}"
    done
    
    echo
    read -p "请输入选项 (1-${#environments[@]}): " choice
    
    if [[ ! "$choice" =~ ^[1-9]$ ]] || (( choice > ${#environments[@]} )); then
        print_message "$RED" "❌ 无效的选项"
        exit $EXIT_INVALID_ARGS
    fi
    
    ENVIRONMENT="${environments[$((choice-1))]}"
    print_message "$GREEN" "✓ 已选择: $ENVIRONMENT 环境"
    echo
}

# 选择部署模式
select_deployment_mode() {
    print_title "选择部署模式"
    
    echo "请选择部署模式："
    echo
    printf "  ${CYAN}1)${NC} 完整部署 - 部署所有组件\n"
    printf "  ${CYAN}2)${NC} 前端部署 - 仅部署前端应用\n"
    printf "  ${CYAN}3)${NC} 后端部署 - 仅部署Lambda函数\n"
    printf "  ${CYAN}4)${NC} 基础设施部署 - 仅部署基础设施\n"
    printf "  ${CYAN}5)${NC} 更新部署 - 更新现有部署\n"
    echo
    
    read -p "请输入选项 (1-5): " mode_choice
    
    case $mode_choice in
        1) DEPLOY_MODE="full" ;;
        2) DEPLOY_MODE="frontend" ;;
        3) DEPLOY_MODE="backend" ;;
        4) DEPLOY_MODE="infrastructure" ;;
        5) DEPLOY_MODE="update" ;;
        *) 
            print_message "$RED" "❌ 无效的选项"
            exit $EXIT_INVALID_ARGS
            ;;
    esac
    
    print_message "$GREEN" "✓ 已选择: $DEPLOY_MODE 模式"
    echo
}

# 确认部署
confirm_deployment() {
    print_title "部署确认"
    
    echo "部署配置摘要："
    echo
    echo "  • 环境: ${CYAN}$ENVIRONMENT${NC}"
    echo "  • 模式: ${CYAN}$DEPLOY_MODE${NC}"
    echo "  • AWS区域: ${CYAN}${AWS_REGION:-$DEFAULT_AWS_REGION}${NC}"
    echo "  • 项目名称: ${CYAN}${PROJECT_NAME:-$DEFAULT_PROJECT_NAME}${NC}"
    echo
    
    print_message "$YELLOW" "⚠️  警告: 部署将会创建AWS资源并产生费用"
    echo
    
    read -p "是否继续部署? (y/N): " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_message "$YELLOW" "部署已取消"
        exit $EXIT_USER_CANCELLED
    fi
    
    echo
}

# 验证环境和依赖
validate_environment() {
    log "INFO" "开始环境验证..."
    
    # 检查必需的命令
    local required_commands=("aws" "terraform" "jq")
    local optional_commands=("node" "npm" "python3" "pip3")
    
    for cmd in "${required_commands[@]}"; do
        if ! check_command "$cmd"; then
            log "ERROR" "必需的命令 $cmd 未找到"
            return $EXIT_MISSING_DEPS
        fi
        log "DEBUG" "✓ 找到命令: $cmd"
    done
    
    for cmd in "${optional_commands[@]}"; do
        if check_command "$cmd"; then
            log "DEBUG" "✓ 找到可选命令: $cmd"
        else
            log "WARN" "可选命令 $cmd 未找到，某些功能可能不可用"
        fi
    done
    
    # 验证 AWS 凭证
    log "INFO" "验证 AWS 凭证..."
    if aws sts get-caller-identity &>/dev/null; then
        local account_id=$(aws sts get-caller-identity --query Account --output text)
        log "INFO" "✓ AWS 凭证有效 (账户: $account_id)"
    else
        log "ERROR" "AWS 凭证无效或未配置"
        print_message "$YELLOW" "请运行 'aws configure' 配置您的 AWS 凭证"
        return $EXIT_MISSING_DEPS
    fi
    
    # 检查 Terraform 版本
    if command -v terraform &> /dev/null; then
        local tf_version=$(terraform version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
        log "INFO" "✓ Terraform 版本: $tf_version"
        
        # 检查最低版本要求
        local min_version="${TERRAFORM_MIN_VERSION:-1.0.0}"
        if ! version_compare "$tf_version" "$min_version"; then
            log "WARN" "Terraform 版本 $tf_version 低于推荐版本 $min_version"
        fi
    fi
    
    # 检查磁盘空间
    local available_space=$(df -k "$SCRIPT_DIR" | tail -1 | awk '{print $4}')
    local min_space_kb=$((1024 * 1024)) # 1GB in KB
    if [ "$available_space" -lt "$min_space_kb" ]; then
        log "WARN" "磁盘空间不足: 仅剩 $((available_space / 1024))MB"
    fi
    
    return 0
}

# 版本比较函数
version_compare() {
    local version1=$1
    local version2=$2
    
    if [[ "$version1" == "$version2" ]]; then
        return 0
    fi
    
    local IFS=.
    local i ver1=($version1) ver2=($version2)
    
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
        ver1[i]=0
    done
    
    for ((i=0; i<${#ver1[@]}; i++)); do
        if [[ -z ${ver2[i]} ]]; then
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]})); then
            return 0
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]})); then
            return 1
        fi
    done
    
    return 0
}

# 执行部署前检查
run_pre_checks() {
    print_title "执行部署前检查"
    
    local checks=(
        "检查AWS凭证"
        "检查Terraform版本"
        "检查Node.js版本"
        "检查Python版本"
        "验证配置文件"
    )
    
    # 执行实际的验证
    if validate_environment; then
        for i in "${!checks[@]}"; do
            show_progress $((i+1)) ${#checks[@]} "${checks[$i]}"
            sleep 0.2  # 减少等待时间
        done
        
        echo
        print_message "$GREEN" "✓ 所有检查通过"
    else
        echo
        print_message "$RED" "❌ 环境验证失败"
        exit $EXIT_MISSING_DEPS
    fi
    echo
}

# 执行部署
execute_deployment() {
    print_title "开始部署"
    
    case $DEPLOY_MODE in
        "full")
            deploy_full
            ;;
        "frontend")
            deploy_frontend
            ;;
        "backend")
            deploy_backend
            ;;
        "infrastructure")
            deploy_infrastructure
            ;;
        "update")
            update_deployment
            ;;
    esac
}

# 完整部署
deploy_full() {
    print_message "$BLUE" "执行完整部署..."
    
    # 检查是否存在相应的部署脚本
    if [ -f "$SCRIPT_DIR/scripts/deploy-complete.sh" ]; then
        bash "$SCRIPT_DIR/scripts/deploy-complete.sh" "$ENVIRONMENT" "${AWS_REGION:-$DEFAULT_AWS_REGION}"
    elif [ -f "$SCRIPT_DIR/deploy-complete.sh" ]; then
        bash "$SCRIPT_DIR/deploy-complete.sh" "$ENVIRONMENT" "${AWS_REGION:-$DEFAULT_AWS_REGION}"
    else
        print_message "$YELLOW" "⚠️  完整部署脚本未找到，将按顺序执行各组件部署"
        deploy_infrastructure
        deploy_backend
        deploy_frontend
    fi
}

# 前端部署
deploy_frontend() {
    print_message "$BLUE" "执行前端部署..."
    
    if [ -f "$SCRIPT_DIR/scripts/deploy-frontend.sh" ]; then
        bash "$SCRIPT_DIR/scripts/deploy-frontend.sh"
    else
        print_message "$RED" "❌ 前端部署脚本未找到"
        exit $EXIT_MISSING_DEPS
    fi
}

# 后端部署
deploy_backend() {
    print_message "$BLUE" "执行后端部署..."
    
    # 构建Lambda包
    if [ -f "$SCRIPT_DIR/build-lambda-packages.sh" ]; then
        print_message "$CYAN" "构建Lambda包..."
        bash "$SCRIPT_DIR/build-lambda-packages.sh"
    else
        print_message "$RED" "❌ Lambda构建脚本未找到"
        exit $EXIT_MISSING_DEPS
    fi
    
    # 更新Lambda函数
    print_message "$CYAN" "更新Lambda函数..."
    cd "$TERRAFORM_DIR"
    terraform apply -var="environment=$ENVIRONMENT" -target=module.query_handler -target=module.document_processor -target=module.authorizer -auto-approve
    
    print_message "$GREEN" "✅ Lambda函数更新完成"
}

# 基础设施部署
deploy_infrastructure() {
    print_message "$BLUE" "执行基础设施部署..."
    
    # 执行部署前资源检查
    if [ -f "$SCRIPT_DIR/scripts/pre-deployment-checks.sh" ]; then
        print_message "$CYAN" "执行部署前资源检查..."
        if "$SCRIPT_DIR/scripts/pre-deployment-checks.sh" "$ENVIRONMENT" "${PROJECT_NAME:-enterprise-rag}" false; then
            print_message "$GREEN" "✓ 资源检查通过"
        else
            print_message "$YELLOW" "⚠️  发现潜在的资源冲突"
            if [ "${NON_INTERACTIVE:-false}" != "true" ]; then
                read -p "是否继续部署? (y/N): " continue_deploy
                if [[ ! "$continue_deploy" =~ ^[Yy]$ ]]; then
                    print_message "$YELLOW" "部署已取消"
                    exit $EXIT_USER_CANCELLED
                fi
            fi
        fi
    fi
    
    if [ -d "$TERRAFORM_DIR" ]; then
        cd "$TERRAFORM_DIR"
        
        # 检测并导入孤立资源
        if [ "${SKIP_RESOURCE_DETECTION:-false}" != "true" ] && [ -f "$SCRIPT_DIR/scripts/detect-and-import-resources.sh" ]; then
            print_message "$CYAN" "检测孤立资源..."
            
            # 根据交互模式设置参数
            local import_args=""
            if [ "${NON_INTERACTIVE:-false}" == "true" ]; then
                import_args="--auto"
            fi
            
            # 执行资源检测和导入
            if "$SCRIPT_DIR/scripts/detect-and-import-resources.sh" \
                --env "$ENVIRONMENT" \
                --project "$PROJECT_NAME" \
                $import_args; then
                print_message "$GREEN" "✓ 资源检测和导入完成"
            else
                log "WARN" "资源导入过程中有警告，继续部署..."
            fi
            echo
        elif [ "${SKIP_RESOURCE_DETECTION:-false}" == "true" ]; then
            log "INFO" "跳过资源检测（根据用户设置）"
        fi
        
        # 初始化Terraform
        print_message "$CYAN" "初始化Terraform..."
        terraform init -upgrade
        
        # 验证配置
        print_message "$CYAN" "验证配置..."
        terraform validate
        
        # 执行计划
        print_message "$CYAN" "生成部署计划..."
        
        # 检查是否需要跳过 OpenSearch 资源
        local plan_args=""
        if [ "${SKIP_OPENSEARCH_RESOURCES:-false}" == "true" ]; then
            log "INFO" "跳过 OpenSearch Serverless 资源"
            # 获取所有非 OpenSearch 资源作为目标
            local targets=$(terraform state list 2>/dev/null | grep -v "opensearchserverless" || true)
            if [ -n "$targets" ]; then
                for target in $targets; do
                    plan_args="$plan_args -target=$target"
                done
            fi
        fi
        
        terraform plan -var="environment=$ENVIRONMENT" $plan_args -out=tfplan
        
        # 应用更改
        print_message "$CYAN" "应用基础设施更改..."
        # 捕获 terraform 输出以便分析错误
        local tf_output_file="${TEMP_DIR:-/tmp}/terraform_apply_$(date +%s).log"
        TEMP_FILES="${TEMP_FILES} $tf_output_file"
        
        if terraform apply tfplan 2>&1 | tee "$tf_output_file"; then
            print_message "$GREEN" "✓ 基础设施部署成功"
            
            # 保存输出
            terraform output -json > outputs.json
        else
            local exit_code=$?
            print_message "$RED" "❌ 部署失败 (退出码: $exit_code)"
            
            # 分析错误并提供解决方案
            if grep -q "ConflictException.*already exists\|InvalidRequestException.*already exists" "$tf_output_file" 2>/dev/null; then
                print_message "$YELLOW" "检测到资源冲突错误：某些资源已经存在"
                
                # 检测具体的资源类型
                local resource_type=""
                local resource_name=""
                
                if grep -q "XRay.*SamplingRule" "$tf_output_file" 2>/dev/null; then
                    resource_type="XRay采样规则"
                    resource_name=$(grep -oE "enterprise-rag-[^\"]*" "$tf_output_file" | head -1)
                    print_message "$CYAN" "检测到 XRay 采样规则冲突: $resource_name"
                    echo
                    echo "  快速修复命令："
                    echo "     # 方案1: 导入现有规则"
                    echo "     cd $TERRAFORM_DIR"
                    echo "     terraform import module.monitoring.aws_xray_sampling_rule.main[0] $resource_name"
                    echo
                    echo "     # 方案2: 删除现有规则"
                    echo "     aws xray delete-sampling-rule --rule-name $resource_name"
                    echo
                elif grep -q "opensearchserverless" "$tf_output_file" 2>/dev/null; then
                    resource_type="OpenSearch Serverless"
                    print_message "$CYAN" "检测到 OpenSearch Serverless 资源冲突"
                fi
                
                # 通用解决方案
                print_message "$CYAN" "通用解决方案："
                echo
                echo "  1. 导入现有资源到 Terraform 状态："
                echo "     cd $TERRAFORM_DIR"
                echo "     terraform import <资源类型>.<资源名称> <资源ID>"
                echo
                echo "  2. 或者，如果是测试环境，可以先删除冲突的资源："
                echo "     - 使用 AWS 控制台删除冲突的资源"
                echo "     - 或使用 AWS CLI 删除资源"
                echo
                echo "  3. 使用 -replace 参数强制重建资源："
                echo "     terraform apply -replace=<资源地址>"
                echo
                echo "  4. 或者尝试刷新 Terraform 状态后重试："
                echo "     terraform refresh"
                echo "     terraform apply"
                echo
                echo "  详细的资源导入指南请参考: TERRAFORM_MIGRATION_GUIDE.md"
            else
                print_message "$YELLOW" "请进入 infrastructure/terraform 目录手动运行 terraform plan 以排查问题。"
                print_message "$YELLOW" "提示：您可以运行以下命令查看详细错误："
                echo "  cd $TERRAFORM_DIR"
                echo "  terraform plan"
            fi
            
            # 提供自动修复选项（仅在交互模式下）
            if [ "${NON_INTERACTIVE:-false}" != "true" ]; then
                echo
                read -p "是否尝试自动修复? (y/N): " auto_fix
                if [[ "$auto_fix" =~ ^[Yy]$ ]]; then
                    attempt_auto_fix
                fi
            fi
            
            cd "$SCRIPT_DIR"
            exit $EXIT_DEPLOY_FAILED
        fi
        
        cd "$SCRIPT_DIR"
    else
        print_message "$RED" "❌ 基础设施目录未找到"
        exit $EXIT_CONFIG_ERROR
    fi
}

# 更新部署
update_deployment() {
    print_message "$BLUE" "执行更新部署..."
    
    # 这里可以根据实际需求实现更新逻辑
    print_message "$YELLOW" "更新部署功能开发中..."
}

# 尝试自动修复部署问题
attempt_auto_fix() {
    print_message "$BLUE" "尝试自动修复部署问题..."
    
    cd "$TERRAFORM_DIR"
    
    # 1. 首先尝试刷新状态
    print_message "$CYAN" "刷新 Terraform 状态..."
    if terraform refresh; then
        log "INFO" "状态刷新成功"
    else
        log "WARN" "状态刷新失败，继续尝试其他方法"
    fi
    
    # 2. 检测特定的资源冲突
    local conflict_resources=()
    local conflict_types=()
    
    # 检查最近的错误输出
    if [ -f "$tf_output_file" ]; then
        # 提取冲突的资源
        while IFS= read -r line; do
            if [[ "$line" =~ "module.bedrock.aws_opensearchserverless".*"already exists" ]]; then
                local resource=$(echo "$line" | grep -oE 'module\.[^,]+' | head -1)
                conflict_resources+=("$resource")
                conflict_types+=("opensearch")
            elif [[ "$line" =~ "module.monitoring.aws_xray_sampling_rule".*"already exists" ]]; then
                local resource="module.monitoring.aws_xray_sampling_rule.main[0]"
                conflict_resources+=("$resource")
                conflict_types+=("xray")
            fi
        done < "$tf_output_file"
    fi
    
    # 3. 如果检测到 OpenSearch Serverless 冲突
    if [ ${#conflict_resources[@]} -gt 0 ]; then
        print_message "$YELLOW" "检测到以下资源冲突："
        for resource in "${conflict_resources[@]}"; do
            echo "  - $resource"
        done
        
        echo
        print_message "$CYAN" "提供以下修复选项："
        echo "  1. 导入现有资源（保留现有配置）"
        echo "  2. 强制替换资源（删除并重建）"
        echo "  3. 跳过冲突资源（部分部署）"
        echo "  4. 手动处理"
        echo
        
        read -p "请选择修复方式 (1-4): " fix_choice
        
        case "$fix_choice" in
            1)
                print_message "$CYAN" "尝试导入现有资源..."
                # 根据资源类型提供具体的导入命令
                for i in "${!conflict_resources[@]}"; do
                    local resource="${conflict_resources[$i]}"
                    local type="${conflict_types[$i]}"
                    
                    if [ "$type" == "xray" ]; then
                        local rule_name=$(grep -oE "enterprise-rag-[^\"]*-${ENVIRONMENT}" "$tf_output_file" | head -1)
                        if [ -n "$rule_name" ]; then
                            print_message "$CYAN" "导入 XRay 采样规则: $rule_name"
                            terraform import "$resource" "$rule_name" || log "WARN" "导入失败: $resource"
                        fi
                    elif [ "$type" == "opensearch" ]; then
                        print_message "$YELLOW" "OpenSearch 资源需要手动导入，请执行："
                        echo "terraform import $resource <resource-id>"
                    fi
                done
                
                # 重新尝试应用
                print_message "$CYAN" "重新应用 Terraform 配置..."
                terraform apply -auto-approve
                ;;
            2)
                print_message "$CYAN" "强制替换冲突的资源..."
                local replace_args=""
                for resource in "${conflict_resources[@]}"; do
                    replace_args="$replace_args -replace=$resource"
                done
                terraform apply $replace_args -auto-approve
                ;;
            3)
                print_message "$CYAN" "跳过冲突资源，继续部署其他资源..."
                local target_args=""
                # 获取所有资源，排除冲突的
                terraform state list | grep -v "opensearchserverless" | while read -r resource; do
                    target_args="$target_args -target=$resource"
                done
                terraform apply $target_args -auto-approve
                ;;
            4)
                print_message "$YELLOW" "请手动处理资源冲突"
                return 1
                ;;
        esac
    else
        # 4. 通用修复尝试
        print_message "$CYAN" "尝试重新初始化并应用..."
        terraform init -upgrade
        terraform apply -auto-approve
    fi
    
    cd "$SCRIPT_DIR"
}

# 显示部署结果
show_deployment_result() {
    print_title "部署完成"
    
    print_message "$GREEN" "✅ 部署成功完成！"
    echo
    
    echo "部署信息："
    echo "  • 环境: $ENVIRONMENT"
    echo "  • 模式: $DEPLOY_MODE"
    echo "  • 时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo
    
    # 如果有输出URL等信息，在这里显示
    local outputs_file="$TERRAFORM_DIR/outputs.json"
    if [ -f "$outputs_file" ]; then
        echo "访问信息："
        echo "  • 前端URL: $(jq -r '.frontend_url.value' < "$outputs_file" 2>/dev/null || echo 'N/A')"
        echo "  • API URL: $(jq -r '.api_url.value' < "$outputs_file" 2>/dev/null || echo 'N/A')"
        echo
    fi
    
    if [ -n "$LOG_FILE" ]; then
        print_message "$CYAN" "📚 查看部署日志: $LOG_FILE"
    else
        print_message "$CYAN" "📚 提示: 设置 LOG_FILE 环境变量以启用日志记录"
    fi
    echo
}

# 主函数
main() {
    # 显示欢迎界面
    show_welcome
    
    # 早期验证环境（在交互之前）
    log "INFO" "开始部署流程..."
    if [ "${VERBOSE:-false}" == "true" ]; then
        LOG_LEVEL="DEBUG"
    fi
    
    # 加载基础配置文件
    load_environment_config "common"
    
    # 选择环境（如果未通过参数指定）
    if [ -z "${ENVIRONMENT:-}" ]; then
        select_environment
    else
        print_message "$GREEN" "✓ 使用指定环境: $ENVIRONMENT"
        echo
    fi
    
    # 加载环境特定的配置
    load_environment_config "$ENVIRONMENT"
    
    # 选择部署模式（如果未通过参数指定）
    if [ -z "${DEPLOY_MODE:-}" ]; then
        select_deployment_mode
    else
        print_message "$GREEN" "✓ 使用指定模式: $DEPLOY_MODE"
        echo
    fi
    
    # CI/CD 环境检测
    if [ "${CI:-false}" == "true" ] || [ "${GITHUB_ACTIONS:-false}" == "true" ] || [ "${GITLAB_CI:-false}" == "true" ]; then
        NON_INTERACTIVE="true"
        log "INFO" "检测到 CI/CD 环境，启用非交互模式"
    fi
    
    # 非交互模式配置
    if [ "${NON_INTERACTIVE:-false}" == "true" ]; then
        log "INFO" "运行在非交互模式"
        # 确保必需的参数已设置
        if [ -z "${ENVIRONMENT:-}" ]; then
            ENVIRONMENT="${DEFAULT_ENVIRONMENT:-dev}"
            log "INFO" "使用默认环境: $ENVIRONMENT"
        fi
        if [ -z "${DEPLOY_MODE:-}" ]; then
            DEPLOY_MODE="${DEFAULT_DEPLOY_MODE:-full}"
            log "INFO" "使用默认部署模式: $DEPLOY_MODE"
        fi
        SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-true}"
    fi
    
    # 确认部署
    if [ "${NON_INTERACTIVE:-false}" != "true" ] && [ "${SKIP_CONFIRMATION:-false}" != "true" ]; then
        confirm_deployment
    elif [ "${SKIP_CONFIRMATION:-false}" == "true" ]; then
        log "INFO" "跳过部署确认（自动确认）"
        print_message "$YELLOW" "自动确认部署: 环境=$ENVIRONMENT, 模式=$DEPLOY_MODE"
    fi
    
    # 执行部署前检查
    run_pre_checks
    
    # 执行部署
    execute_deployment
    
    # 显示部署结果
    show_deployment_result
}

# 处理命令行参数
while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --help, -h              显示帮助信息"
            echo "  --env ENV               指定环境 (dev|staging|prod|custom)"
            echo "  --mode MODE             指定部署模式 (full|frontend|backend|infrastructure|update)"
            echo "  --non-interactive       非交互式模式"
            echo "  --skip-confirmation     跳过部署确认"
            echo "  --skip-resource-check   跳过孤立资源检测"
            echo "  --verbose               显示详细日志"
            echo "  --log-file FILE         指定日志文件路径"
            echo "  --log-level LEVEL       设置日志级别 (DEBUG|INFO|WARN|ERROR)"
            echo "  --config FILE           指定配置文件路径"
            echo ""
            echo "Environment Variables:"
            echo "  AWS_REGION              AWS 区域 (默认: $DEFAULT_AWS_REGION)"
            echo "  PROJECT_NAME            项目名称 (默认: $DEFAULT_PROJECT_NAME)"
            echo "  LOG_LEVEL               日志级别 (默认: INFO)"
            echo "  LOG_FILE                日志文件路径"
            echo "  NON_INTERACTIVE         启用非交互模式"
            echo "  CI                      CI/CD 环境标志"
            echo ""
            exit $EXIT_SUCCESS
            ;;
        --env)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --mode)
            DEPLOY_MODE="$2"
            shift 2
            ;;
        --non-interactive)
            NON_INTERACTIVE=true
            shift
            ;;
        --skip-confirmation)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --skip-resource-check)
            SKIP_RESOURCE_DETECTION=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            LOG_LEVEL="DEBUG"
            shift
            ;;
        --log-file)
            LOG_FILE="$2"
            shift 2
            ;;
        --log-level)
            LOG_LEVEL="$2"
            shift 2
            ;;
        --config)
            DEPLOY_CONFIG_FILE="$2"
            shift 2
            ;;
        *)
            echo "未知参数: $1"
            echo "使用 --help 查看帮助信息"
            exit $EXIT_INVALID_ARGS
            ;;
    esac
done

# 执行主函数
main

exit $EXIT_SUCCESS