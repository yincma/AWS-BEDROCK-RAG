#!/bin/bash

# AWS 资源孤立检测和自动导入脚本
# 功能：检测AWS中存在但不在Terraform状态中的资源，并自动导入
# 版本：1.0

set -euo pipefail

# 脚本目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="${TERRAFORM_DIR:-$PROJECT_ROOT/infrastructure/terraform}"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 配置
DRY_RUN="${DRY_RUN:-false}"
AUTO_IMPORT="${AUTO_IMPORT:-false}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
# 从terraform变量或环境变量获取项目名称，避免硬编码
if [ -z "${PROJECT_NAME:-}" ]; then
    # 尝试从terraform变量文件获取
    if [ -f "$TERRAFORM_DIR/terraform.tfvars" ]; then
        PROJECT_NAME=$(grep -E "^project_name\s*=" "$TERRAFORM_DIR/terraform.tfvars" 2>/dev/null | sed 's/.*=\s*"\(.*\)"/\1/' | tr -d ' ' || echo "")
    fi
    # 如果还是空，尝试从环境特定的变量文件获取
    if [ -z "$PROJECT_NAME" ] && [ -f "$TERRAFORM_DIR/environments/${ENVIRONMENT}/terraform.tfvars" ]; then
        PROJECT_NAME=$(grep -E "^project_name\s*=" "$TERRAFORM_DIR/environments/${ENVIRONMENT}/terraform.tfvars" 2>/dev/null | sed 's/.*=\s*"\(.*\)"/\1/' | tr -d ' ' || echo "")
    fi
    # 最后使用默认值
    PROJECT_NAME="${PROJECT_NAME:-rag-system}"
fi
LOG_FILE="${LOG_FILE:-$SCRIPT_DIR/resource-import-$(date +%Y%m%d-%H%M%S).log}"

# 资源类型定义和导入规则
declare -A RESOURCE_TYPES=(
    ["xray_sampling_rule"]="aws_xray_sampling_rule"
    ["opensearch_domain"]="aws_opensearchserverless_collection"
    ["opensearch_security_policy"]="aws_opensearchserverless_security_policy"
    ["s3_bucket"]="aws_s3_bucket"
    ["lambda_function"]="aws_lambda_function"
    ["api_gateway_rest_api"]="aws_api_gateway_rest_api"
    ["cloudwatch_log_group"]="aws_cloudwatch_log_group"
    ["iam_role"]="aws_iam_role"
    ["dynamodb_table"]="aws_dynamodb_table"
)

# 初始化日志
init_log() {
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "=== 资源导入日志 - $(date) ===" > "$LOG_FILE"
    echo "环境: $ENVIRONMENT" >> "$LOG_FILE"
    echo "项目: $PROJECT_NAME" >> "$LOG_FILE"
    echo "===========================================" >> "$LOG_FILE"
}

# 日志函数
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    case "$level" in
        ERROR) echo -e "${RED}[$level] $message${NC}" >&2 ;;
        WARN)  echo -e "${YELLOW}[$level] $message${NC}" ;;
        INFO)  echo -e "${GREEN}[$level] $message${NC}" ;;
        DEBUG) echo -e "${GRAY}[$level] $message${NC}" ;;
    esac
}

# 打印标题
print_title() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# 检查依赖
check_dependencies() {
    local deps=("aws" "terraform" "jq")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log "ERROR" "缺少必需的命令: $dep"
            exit 1
        fi
    done
}

# 获取Terraform资源地址
get_terraform_resource_addresses() {
    local resource_type=$1
    cd "$TERRAFORM_DIR"
    
    # 获取计划中的资源
    terraform plan -no-color 2>/dev/null | grep -E "^.*# ${resource_type}\." | awk '{print $2}' | sort -u || true
}

# 检测XRay采样规则
detect_xray_sampling_rules() {
    log "INFO" "检测XRay采样规则..."
    
    local expected_rule_name="${PROJECT_NAME}-sampling-${ENVIRONMENT}"
    local aws_rules=$(aws xray get-sampling-rules --query 'SamplingRuleRecords[].SamplingRule.ruleName' --output json | jq -r '.[]' | grep "${PROJECT_NAME}" || true)
    
    local orphaned_rules=()
    
    for rule in $aws_rules; do
        # 检查是否在Terraform状态中
        if ! terraform state list 2>/dev/null | grep -q "aws_xray_sampling_rule.*$rule"; then
            orphaned_rules+=("$rule")
            log "WARN" "发现孤立的XRay采样规则: $rule"
        fi
    done
    
    echo "${orphaned_rules[@]}"
}

# 检测S3存储桶
detect_s3_buckets() {
    log "INFO" "检测S3存储桶..."
    
    local bucket_prefix="${PROJECT_NAME}-${ENVIRONMENT}"
    local aws_buckets=$(aws s3api list-buckets --query "Buckets[?contains(Name, '${bucket_prefix}')].Name" --output json | jq -r '.[]' || true)
    
    local orphaned_buckets=()
    
    for bucket in $aws_buckets; do
        if ! terraform state list 2>/dev/null | grep -q "aws_s3_bucket.*$bucket"; then
            orphaned_buckets+=("$bucket")
            log "WARN" "发现孤立的S3存储桶: $bucket"
        fi
    done
    
    echo "${orphaned_buckets[@]}"
}

# 检测Lambda函数
detect_lambda_functions() {
    log "INFO" "检测Lambda函数..."
    
    local function_prefix="${PROJECT_NAME}-${ENVIRONMENT}"
    local aws_functions=$(aws lambda list-functions --query "Functions[?contains(FunctionName, '${function_prefix}')].FunctionName" --output json | jq -r '.[]' || true)
    
    local orphaned_functions=()
    
    for func in $aws_functions; do
        if ! terraform state list 2>/dev/null | grep -q "aws_lambda_function.*$func"; then
            orphaned_functions+=("$func")
            log "WARN" "发现孤立的Lambda函数: $func"
        fi
    done
    
    echo "${orphaned_functions[@]}"
}

# 检测CloudWatch日志组
detect_log_groups() {
    log "INFO" "检测CloudWatch日志组..."
    
    local log_prefix="/aws/lambda/${PROJECT_NAME}-${ENVIRONMENT}"
    local aws_logs=$(aws logs describe-log-groups --log-group-name-prefix "$log_prefix" --query 'logGroups[].logGroupName' --output json | jq -r '.[]' || true)
    
    local orphaned_logs=()
    
    for log_group in $aws_logs; do
        if ! terraform state list 2>/dev/null | grep -q "aws_cloudwatch_log_group.*$(echo $log_group | sed 's/\//\\\//g')"; then
            orphaned_logs+=("$log_group")
            log "WARN" "发现孤立的日志组: $log_group"
        fi
    done
    
    echo "${orphaned_logs[@]}"
}

# 生成导入命令
generate_import_command() {
    local resource_type=$1
    local resource_name=$2
    local terraform_address=$3
    
    case "$resource_type" in
        "xray_sampling_rule")
            echo "terraform import $terraform_address $resource_name"
            ;;
        "s3_bucket")
            echo "terraform import $terraform_address $resource_name"
            ;;
        "lambda_function")
            echo "terraform import $terraform_address $resource_name"
            ;;
        "cloudwatch_log_group")
            echo "terraform import $terraform_address $resource_name"
            ;;
        *)
            log "WARN" "未知的资源类型: $resource_type"
            return 1
            ;;
    esac
}

# 执行导入
execute_import() {
    local import_command=$1
    
    if [ "$DRY_RUN" == "true" ]; then
        log "INFO" "[DRY RUN] 将执行: $import_command"
        return 0
    fi
    
    log "INFO" "执行导入: $import_command"
    
    cd "$TERRAFORM_DIR"
    if eval "$import_command" >> "$LOG_FILE" 2>&1; then
        log "INFO" "导入成功"
        return 0
    else
        log "ERROR" "导入失败: $import_command"
        return 1
    fi
}

# 交互式导入
interactive_import() {
    local resource_type=$1
    local resource_name=$2
    local suggested_address=$3
    
    echo
    echo -e "${YELLOW}发现孤立资源:${NC}"
    echo -e "  类型: ${CYAN}$resource_type${NC}"
    echo -e "  名称: ${CYAN}$resource_name${NC}"
    echo -e "  建议地址: ${CYAN}$suggested_address${NC}"
    echo
    
    if [ "$AUTO_IMPORT" == "true" ]; then
        log "INFO" "自动导入模式：导入资源 $resource_name"
        local import_cmd=$(generate_import_command "$resource_type" "$resource_name" "$suggested_address")
        execute_import "$import_cmd"
        return
    fi
    
    echo "选项："
    echo "  1) 导入到建议的地址"
    echo "  2) 输入自定义地址"
    echo "  3) 跳过此资源"
    echo "  4) 删除AWS中的资源"
    echo
    
    read -p "请选择 (1-4): " choice
    
    case "$choice" in
        1)
            local import_cmd=$(generate_import_command "$resource_type" "$resource_name" "$suggested_address")
            execute_import "$import_cmd"
            ;;
        2)
            read -p "输入Terraform资源地址: " custom_address
            local import_cmd=$(generate_import_command "$resource_type" "$resource_name" "$custom_address")
            execute_import "$import_cmd"
            ;;
        3)
            log "INFO" "跳过资源: $resource_name"
            ;;
        4)
            if confirm_deletion "$resource_type" "$resource_name"; then
                delete_aws_resource "$resource_type" "$resource_name"
            fi
            ;;
        *)
            log "WARN" "无效选择，跳过资源"
            ;;
    esac
}

# 确认删除
confirm_deletion() {
    local resource_type=$1
    local resource_name=$2
    
    echo -e "${RED}警告: 即将删除AWS资源${NC}"
    echo -e "类型: $resource_type"
    echo -e "名称: $resource_name"
    echo
    read -p "确定要删除吗? (yes/no): " confirm
    
    [[ "$confirm" == "yes" ]]
}

# 删除AWS资源
delete_aws_resource() {
    local resource_type=$1
    local resource_name=$2
    
    if [ "$DRY_RUN" == "true" ]; then
        log "INFO" "[DRY RUN] 将删除: $resource_type - $resource_name"
        return 0
    fi
    
    case "$resource_type" in
        "xray_sampling_rule")
            aws xray delete-sampling-rule --rule-name "$resource_name"
            ;;
        "s3_bucket")
            # 先清空桶
            aws s3 rm "s3://$resource_name" --recursive
            aws s3api delete-bucket --bucket "$resource_name"
            ;;
        "lambda_function")
            aws lambda delete-function --function-name "$resource_name"
            ;;
        "cloudwatch_log_group")
            aws logs delete-log-group --log-group-name "$resource_name"
            ;;
        *)
            log "ERROR" "不支持删除的资源类型: $resource_type"
            return 1
            ;;
    esac
    
    log "INFO" "已删除资源: $resource_type - $resource_name"
}

# 查找最佳匹配的Terraform地址
find_terraform_address() {
    local resource_type=$1
    local resource_name=$2
    
    cd "$TERRAFORM_DIR"
    
    # 首先尝试从terraform state中查找类似的资源
    local existing_resources=$(terraform state list 2>/dev/null | grep "${RESOURCE_TYPES[$resource_type]}" || true)
    
    # 根据资源类型和命名模式推测Terraform地址
    case "$resource_type" in
        "xray_sampling_rule")
            # 检查是否有monitoring模块
            if echo "$existing_resources" | grep -q "module.monitoring"; then
                echo "module.monitoring.aws_xray_sampling_rule.main[0]"
            else
                echo "aws_xray_sampling_rule.main"
            fi
            ;;
        "s3_bucket")
            # 基于bucket用途推测模块
            if [[ "$resource_name" == *"raw-data"* ]] || [[ "$resource_name" == *"documents"* ]]; then
                if echo "$existing_resources" | grep -q "module.storage"; then
                    echo "module.storage.aws_s3_bucket.raw_data"
                else
                    echo "aws_s3_bucket.raw_data"
                fi
            elif [[ "$resource_name" == *"processed-data"* ]]; then
                if echo "$existing_resources" | grep -q "module.storage"; then
                    echo "module.storage.aws_s3_bucket.processed_data"
                else
                    echo "aws_s3_bucket.processed_data"
                fi
            elif [[ "$resource_name" == *"frontend"* ]]; then
                if echo "$existing_resources" | grep -q "module.frontend"; then
                    echo "module.frontend.aws_s3_bucket.frontend"
                else
                    echo "aws_s3_bucket.frontend"
                fi
            else
                echo "aws_s3_bucket.${resource_name//-/_}"
            fi
            ;;
        "lambda_function")
            # 基于函数名推测模块
            local function_base=$(echo "$resource_name" | sed "s/${PROJECT_NAME}-//" | sed "s/-${ENVIRONMENT}//")
            
            if [[ "$function_base" == *"query-handler"* ]] || [[ "$function_base" == *"query_handler"* ]]; then
                if echo "$existing_resources" | grep -q "module.query_handler"; then
                    echo "module.query_handler.aws_lambda_function.main"
                else
                    echo "aws_lambda_function.query_handler"
                fi
            elif [[ "$function_base" == *"document-processor"* ]] || [[ "$function_base" == *"document_processor"* ]]; then
                if echo "$existing_resources" | grep -q "module.document_processor"; then
                    echo "module.document_processor.aws_lambda_function.main"
                else
                    echo "aws_lambda_function.document_processor"
                fi
            elif [[ "$function_base" == *"authorizer"* ]]; then
                if echo "$existing_resources" | grep -q "module.authorizer"; then
                    echo "module.authorizer.aws_lambda_function.main"
                else
                    echo "aws_lambda_function.authorizer"
                fi
            else
                echo "aws_lambda_function.${function_base//-/_}"
            fi
            ;;
        "cloudwatch_log_group")
            local clean_name=$(echo "$resource_name" | sed 's/\/aws\/lambda\///' | sed 's/-/_/g')
            echo "aws_cloudwatch_log_group.$clean_name"
            ;;
        *)
            echo "aws_${resource_type}.${resource_name//-/_}"
            ;;
    esac
}

# 主检测流程
main() {
    init_log
    print_title "🔍 AWS资源孤立检测和导入工具"
    
    log "INFO" "开始资源检测..."
    check_dependencies
    
    # 确保在Terraform目录中
    if [ ! -d "$TERRAFORM_DIR" ]; then
        log "ERROR" "Terraform目录不存在: $TERRAFORM_DIR"
        exit 1
    fi
    
    cd "$TERRAFORM_DIR"
    
    # 初始化Terraform（如果需要）
    if [ ! -d ".terraform" ]; then
        log "INFO" "初始化Terraform..."
        terraform init
    fi
    
    # 刷新状态
    log "INFO" "刷新Terraform状态..."
    terraform refresh > /dev/null 2>&1 || log "WARN" "状态刷新失败，继续..."
    
    # 检测各类资源
    local total_orphaned=0
    local imported_count=0
    
    # XRay采样规则
    echo
    print_title "检测XRay采样规则"
    local xray_rules=($(detect_xray_sampling_rules))
    for rule in "${xray_rules[@]}"; do
        if [ -n "$rule" ]; then
            ((total_orphaned++))
            local suggested_addr=$(find_terraform_address "xray_sampling_rule" "$rule")
            interactive_import "xray_sampling_rule" "$rule" "$suggested_addr"
            [ $? -eq 0 ] && ((imported_count++))
        fi
    done
    
    # S3存储桶
    echo
    print_title "检测S3存储桶"
    local s3_buckets=($(detect_s3_buckets))
    for bucket in "${s3_buckets[@]}"; do
        if [ -n "$bucket" ]; then
            ((total_orphaned++))
            local suggested_addr=$(find_terraform_address "s3_bucket" "$bucket")
            interactive_import "s3_bucket" "$bucket" "$suggested_addr"
            [ $? -eq 0 ] && ((imported_count++))
        fi
    done
    
    # Lambda函数
    echo
    print_title "检测Lambda函数"
    local lambda_functions=($(detect_lambda_functions))
    for func in "${lambda_functions[@]}"; do
        if [ -n "$func" ]; then
            ((total_orphaned++))
            local suggested_addr=$(find_terraform_address "lambda_function" "$func")
            interactive_import "lambda_function" "$func" "$suggested_addr"
            [ $? -eq 0 ] && ((imported_count++))
        fi
    done
    
    # CloudWatch日志组
    echo
    print_title "检测CloudWatch日志组"
    local log_groups=($(detect_log_groups))
    for log_group in "${log_groups[@]}"; do
        if [ -n "$log_group" ]; then
            ((total_orphaned++))
            local suggested_addr=$(find_terraform_address "cloudwatch_log_group" "$log_group")
            interactive_import "cloudwatch_log_group" "$log_group" "$suggested_addr"
            [ $? -eq 0 ] && ((imported_count++))
        fi
    done
    
    # 总结
    echo
    print_title "📊 检测总结"
    echo -e "总计发现孤立资源: ${YELLOW}$total_orphaned${NC}"
    echo -e "成功导入资源数: ${GREEN}$imported_count${NC}"
    echo -e "日志文件: ${CYAN}$LOG_FILE${NC}"
    
    if [ "$total_orphaned" -gt 0 ] && [ "$imported_count" -eq "$total_orphaned" ]; then
        log "INFO" "所有孤立资源已成功导入！"
        return 0
    elif [ "$total_orphaned" -eq 0 ]; then
        log "INFO" "未发现孤立资源，环境干净！"
        return 0
    else
        log "WARN" "部分资源未导入，请查看日志了解详情"
        return 1
    fi
}

# 显示帮助
show_help() {
    cat << EOF
用法: $0 [选项]

选项:
    -h, --help              显示帮助信息
    -d, --dry-run           模拟运行，不执行实际操作
    -a, --auto              自动导入所有检测到的资源
    -e, --env ENV           指定环境 (默认: dev)
    -p, --project NAME      指定项目名称 (默认: 自动检测或rag-system)
    -l, --log FILE          指定日志文件路径

环境变量:
    DRY_RUN                 设置为true启用模拟模式
    AUTO_IMPORT             设置为true启用自动导入
    ENVIRONMENT             部署环境
    PROJECT_NAME            项目名称
    TERRAFORM_DIR           Terraform目录路径

示例:
    # 交互式检测和导入
    $0
    
    # 自动导入所有资源
    $0 --auto
    
    # 模拟运行，查看将执行的操作
    $0 --dry-run
    
    # 指定环境
    $0 --env prod

EOF
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -a|--auto)
            AUTO_IMPORT=true
            shift
            ;;
        -e|--env)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -p|--project)
            PROJECT_NAME="$2"
            shift 2
            ;;
        -l|--log)
            LOG_FILE="$2"
            shift 2
            ;;
        *)
            echo "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
done

# 执行主函数
main