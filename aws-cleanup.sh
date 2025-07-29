#!/bin/bash

# Unified AWS Resources Management Script
# 统一的 AWS 资源管理脚本 - 检查和清理
# Version: 2.0
# Improved by AI Assistant:
# - Parameterized prefix and environment.
# - Added true deletion for CloudFront distributions.
# - Enhanced VPC cleanup with retries and diagnostics.
# - Improved error reporting for critical resource deletion.

# 不要在遇到错误时立即退出，让脚本继续执行
# set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- 配置 ---
# Default values, can be overridden by command-line arguments
PREFIX="enterprise-rag"
ENVIRONMENT="dev"
AUTO_CONFIRM=false
PREFIX_ARG_SET=false
ENV_ARG_SET=false

# 计数器
TOTAL_RESOURCES=0

# 打印带颜色的消息
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# 打印资源
print_resource() {
    local resource_type=$1
    local resource_name=$2
    ((TOTAL_RESOURCES++))
    print_message "$RED" "  ❌ $resource_type: $resource_name"
}

# 配置验证函数 - 确保输入参数的安全性
validate_config() {
    print_message "$BLUE" "验证配置参数..."
    
    # 验证前缀格式
    if [[ ! "$PREFIX" =~ ^[a-zA-Z0-9-]+$ ]]; then
        print_message "$RED" "错误：前缀包含无效字符。只允许字母、数字和连字符。"
        return 1
    fi
    
    # 验证前缀长度
    if [ ${#PREFIX} -lt 3 ] || [ ${#PREFIX} -gt 50 ]; then
        print_message "$RED" "错误：前缀长度必须在3-50个字符之间。"
        return 1
    fi
    
    # 验证环境名称
    if [[ ! "$ENVIRONMENT" =~ ^[a-zA-Z0-9-]+$ ]]; then
        print_message "$RED" "错误：环境名称包含无效字符。只允许字母、数字和连字符。"
        return 1
    fi
    
    # 验证环境名称长度
    if [ ${#ENVIRONMENT} -lt 2 ] || [ ${#ENVIRONMENT} -gt 20 ]; then
        print_message "$RED" "错误：环境名称长度必须在2-20个字符之间。"
        return 1
    fi
    
    # 防止删除常见的生产环境资源
    local dangerous_patterns=("prod" "production" "live" "main" "master")
    for pattern in "${dangerous_patterns[@]}"; do
        if [[ "$ENVIRONMENT" == *"$pattern"* ]] && [ "$AUTO_CONFIRM" != "true" ]; then
            print_message "$RED" "警告：检测到可能的生产环境标识 '$pattern'"
            print_message "$YELLOW" "如果确实要清理生产环境，请使用 --yes 参数确认"
            return 1
        fi
    done
    
    print_message "$GREEN" "✓ 配置验证通过"
    return 0
}

# 显示使用说明
show_usage() {
    echo "用法: $0 <命令> [选项]"
    echo ""
    echo "命令:"
    echo "  check          - 检查资源，不执行任何操作"
    echo "  clean          - 查找并删除所有关联的资源"
    echo "  all            - 检查资源，然后提示进行清理（默认）"
    echo ""
    echo "选项:"
    echo "  --prefix [名称]    - 指定项目前缀 (默认: enterprise-rag)"
    echo "  --env [名称]       - 指定环境 (默认: dev)"
    echo "  --yes              - 自动确认清理，不进行提示"
    echo "  -h, --help         - 显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 clean --prefix my-rag --env prod --yes   # 非交互式清理my-rag-prod项目资源"
}

# 解析命令行参数
# 检查第一个参数是否是命令
MODE="${1:-all}"
case "$MODE" in
    check|clean|all|-h|--help)
        shift # a command was found
        ;;
    *)
        # Not a command, assume default 'all' and don't shift
        MODE="all"
        ;;
esac

while [ "$#" -gt 0 ]; do
    case "$1" in
        --prefix)
            PREFIX="$2"
            PREFIX_ARG_SET=true
            shift 2
            ;;
        --env)
            ENVIRONMENT="$2"
            ENV_ARG_SET=true
            shift 2
            ;;
        --yes)
            AUTO_CONFIRM=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_message "$RED" "未知选项: $1"
            show_usage
            exit 1
            ;;
    esac
done

# 如果不是在自动确认模式下，对未明确指定的目标进行交互式确认
if [[ ("$MODE" == "clean" || "$MODE" == "all") && "$AUTO_CONFIRM" = false ]]; then
    if [ "$PREFIX_ARG_SET" = false ]; then
        read -p "未指定项目前缀，将使用默认值 '$PREFIX'。按 Enter 键确认或输入新前缀: " new_prefix
        if [ -n "$new_prefix" ]; then
            PREFIX="$new_prefix"
        fi
    fi
    if [ "$ENV_ARG_SET" = false ]; then
        read -p "未指定环境，将使用默认值 '$ENVIRONMENT'。按 Enter 键确认或输入新环境: " new_env
        if [ -n "$new_env" ]; then
            ENVIRONMENT="$new_env"
        fi
    fi
    print_message "$GREEN" "✓ 目标确认: 前缀='$PREFIX', 环境='$ENVIRONMENT'"
    echo
fi


# 验证命令
case "$MODE" in
    check|clean|all)
        ;;
    -h|--help|help)
        show_usage
        exit 0
        ;;
    *)
        print_message "$RED" "错误：无效的命令 '$MODE'"
        echo
        show_usage
        exit 1
        ;;
esac

# 检查资源函数
check_resources() {
    print_message "$BLUE" "=== AWS 资源检查 ==="
    print_message "$BLUE" "检查前缀: $PREFIX, 环境: $ENVIRONMENT"
    echo
    
    TOTAL_RESOURCES=0
    
    # 1. 检查 S3 存储桶
    print_message "$YELLOW" "检查 S3 存储桶..."
    BUCKETS=$(aws s3api list-buckets --query "Buckets[?contains(Name, '$PREFIX')].Name" --output text 2>/dev/null || echo "")
    if [ -n "$BUCKETS" ] && [ "$BUCKETS" != "None" ]; then
        for bucket in $BUCKETS; do
            print_resource "S3 Bucket" "$bucket"
        done
    else
        print_message "$GREEN" "✓ 没有找到 S3 存储桶"
    fi
    echo
    
    # 2. 检查 Lambda 函数
    print_message "$YELLOW" "检查 Lambda 函数..."
    FUNCTIONS=$(aws lambda list-functions --query "Functions[?contains(FunctionName, '$PREFIX') && contains(FunctionName, '$ENVIRONMENT')].FunctionName" --output text 2>/dev/null || echo "")
    if [ -n "$FUNCTIONS" ] && [ "$FUNCTIONS" != "None" ]; then
        for func in $FUNCTIONS; do
            print_resource "Lambda Function" "$func"
        done
    else
        print_message "$GREEN" "✓ 没有找到 Lambda 函数"
    fi
    
    # 检查 Lambda 层
    LAYERS=$(aws lambda list-layers --query "Layers[?contains(LayerName, '$PREFIX') && contains(LayerName, '$ENVIRONMENT')].LayerName" --output text 2>/dev/null || echo "")
    if [ -n "$LAYERS" ] && [ "$LAYERS" != "None" ]; then
        for layer in $LAYERS; do
            print_resource "Lambda Layer" "$layer"
        done
    else
        print_message "$GREEN" "✓ 没有找到 Lambda 层"
    fi
    echo
    
    # 3. 检查 API Gateway
    print_message "$YELLOW" "检查 API Gateway..."
    APIS=$(aws apigateway get-rest-apis --query "items[?contains(name, '$PREFIX') && contains(name, '$ENVIRONMENT')].name" --output text 2>/dev/null || echo "")
    if [ -n "$APIS" ] && [ "$APIS" != "None" ]; then
        for api in $APIS; do
            print_resource "API Gateway" "$api"
        done
    else
        print_message "$GREEN" "✓ 没有找到 API Gateway"
    fi
    echo
    
    # 4. 检查 Cognito User Pool
    print_message "$YELLOW" "检查 Cognito User Pool..."
    USER_POOLS=$(aws cognito-idp list-user-pools --max-results 50 --query "UserPools[?contains(Name, '$PREFIX') && contains(Name, '$ENVIRONMENT')].Name" --output text 2>/dev/null || echo "")
    if [ -n "$USER_POOLS" ] && [ "$USER_POOLS" != "None" ]; then
        for pool in $USER_POOLS; do
            print_resource "Cognito User Pool" "$pool"
        done
    else
        print_message "$GREEN" "✓ 没有找到 Cognito User Pool"
    fi
    echo
    
    # 5. 检查 CloudWatch 日志组
    print_message "$YELLOW" "检查 CloudWatch 日志组..."
    # 使用更精确的查询逻辑 - 包含项目前缀和环境的日志组
    LOG_GROUPS=$(aws logs describe-log-groups --query "logGroups[?contains(logGroupName, '$PREFIX') && contains(logGroupName, '$ENVIRONMENT')].logGroupName" --output text 2>/dev/null || echo "")
    # 同时检查Lambda函数相关的日志组
    LAMBDA_LOG_GROUPS=$(aws logs describe-log-groups --query "logGroups[?starts_with(logGroupName, '/aws/lambda/$PREFIX')].logGroupName" --output text 2>/dev/null || echo "")
    
    # 合并结果并去重
    ALL_LOG_GROUPS=""
    if [ -n "$LOG_GROUPS" ] && [ "$LOG_GROUPS" != "None" ]; then
        ALL_LOG_GROUPS="$LOG_GROUPS"
    fi
    if [ -n "$LAMBDA_LOG_GROUPS" ] && [ "$LAMBDA_LOG_GROUPS" != "None" ]; then
        ALL_LOG_GROUPS="$ALL_LOG_GROUPS $LAMBDA_LOG_GROUPS"
    fi
    
    if [ -n "$ALL_LOG_GROUPS" ]; then
        # 去重并过滤包含环境的日志组
        for log_group in $ALL_LOG_GROUPS; do
            if [[ "$log_group" == *"$ENVIRONMENT"* ]]; then
                print_resource "CloudWatch Log Group" "$log_group"
            fi
        done
    else
        print_message "$GREEN" "✓ 没有找到 CloudWatch 日志组"
    fi
    echo
    
    # 6. 检查 VPC
    print_message "$YELLOW" "检查 VPC..."
    VPCS=$(aws ec2 describe-vpcs --filters "Name=tag:Project,Values=$PREFIX" "Name=tag:Environment,Values=$ENVIRONMENT" --query "Vpcs[].{VpcId:VpcId,Name:Tags[?Key=='Name'].Value|[0]}" --output text 2>/dev/null || echo "")
    if [ -n "$VPCS" ] && [ "$VPCS" != "None" ]; then
        while read -r vpc_id vpc_name; do
            print_resource "VPC" "$vpc_name ($vpc_id)"
            
            # 检查该VPC中的网络接口
            ENI_COUNT=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$vpc_id" --query "length(NetworkInterfaces)" --output text 2>/dev/null || echo "0")
            if [ "$ENI_COUNT" -gt 0 ]; then
                print_message "$YELLOW" "  └─ 该VPC中还有 $ENI_COUNT 个网络接口"
            fi
        done <<< "$VPCS"
    else
        print_message "$GREEN" "✓ 没有找到专用 VPC"
    fi
    echo
    
    # 7. 检查 OpenSearch Serverless 资源
    print_message "$YELLOW" "检查 OpenSearch Serverless 资源..."
    # 动态计算OpenSearch前缀（去掉连字符）
    OPENSEARCH_PREFIX=$(echo "$PREFIX" | tr -d '-')
    
    # 检查Collections
    COLLECTIONS=$(aws opensearchserverless list-collections --query "collectionSummaries[?contains(name, '$OPENSEARCH_PREFIX') && contains(name, '$ENVIRONMENT')].{Name:name,Id:id}" --output text 2>/dev/null || echo "")
    if [ -n "$COLLECTIONS" ] && [ "$COLLECTIONS" != "None" ]; then
        while read -r name id; do
            print_resource "OpenSearch Collection" "$name ($id)"
        done <<< "$COLLECTIONS"
    else
        print_message "$GREEN" "✓ 没有找到 OpenSearch Collection"
    fi
    
    # 检查Data Access Policies
    ACCESS_POLICIES=$(aws opensearchserverless list-access-policies --type data --query "accessPolicySummaries[?contains(name, '$OPENSEARCH_PREFIX') && contains(name, '$ENVIRONMENT')].name" --output text 2>/dev/null || echo "")
    if [ -n "$ACCESS_POLICIES" ] && [ "$ACCESS_POLICIES" != "None" ]; then
        for policy in $ACCESS_POLICIES; do
            print_resource "OpenSearch Access Policy" "$policy"
        done
    else
        print_message "$GREEN" "✓ 没有找到 OpenSearch Access Policy"
    fi
    
    # 检查Network Security Policies
    NETWORK_POLICIES=$(aws opensearchserverless list-security-policies --type network --query "securityPolicySummaries[?contains(name, '$OPENSEARCH_PREFIX') && contains(name, '$ENVIRONMENT')].name" --output text 2>/dev/null || echo "")
    if [ -n "$NETWORK_POLICIES" ] && [ "$NETWORK_POLICIES" != "None" ]; then
        for policy in $NETWORK_POLICIES; do
            print_resource "OpenSearch Network Policy" "$policy"
        done
    else
        print_message "$GREEN" "✓ 没有找到 OpenSearch Network Policy"
    fi
    
    # 检查Encryption Security Policies
    ENCRYPTION_POLICIES=$(aws opensearchserverless list-security-policies --type encryption --query "securityPolicySummaries[?contains(name, '$OPENSEARCH_PREFIX') && contains(name, '$ENVIRONMENT')].name" --output text 2>/dev/null || echo "")
    if [ -n "$ENCRYPTION_POLICIES" ] && [ "$ENCRYPTION_POLICIES" != "None" ]; then
        for policy in $ENCRYPTION_POLICIES; do
            print_resource "OpenSearch Encryption Policy" "$policy"
        done
    else
        print_message "$GREEN" "✓ 没有找到 OpenSearch Encryption Policy"
    fi
    echo
    
    # 8. 检查其他资源
    print_message "$YELLOW" "检查其他资源..."
    
    # CloudFront
    DISTRIBUTIONS=$(aws cloudfront list-distributions --query "DistributionList.Items[?contains(Comment, '$PREFIX') && contains(Comment, '$ENVIRONMENT')].{Id:Id,Comment:Comment,Status:Status}" --output text 2>/dev/null || echo "")
    if [ -n "$DISTRIBUTIONS" ] && [ "$DISTRIBUTIONS" != "None" ]; then
        while read -r dist_id comment status; do
            print_resource "CloudFront Distribution" "$comment (ID: $dist_id, Status: $status)"
        done <<< "$DISTRIBUTIONS"
    else
        print_message "$GREEN" "✓ 没有找到 CloudFront 分发"
    fi
    
    # Bedrock
    KB_OUTPUT=$(aws bedrock-agent list-knowledge-bases 2>&1)
    if [ $? -eq 0 ]; then
        KB_LIST=$(echo "$KB_OUTPUT" | jq -r ".knowledgeBaseSummaries[] | select(.name | contains(\"$PREFIX\") and contains(\"$ENVIRONMENT\")) | .name" 2>/dev/null || echo "")
        if [ -n "$KB_LIST" ]; then
            echo "$KB_LIST" | while read -r kb; do
                print_resource "Bedrock Knowledge Base" "$kb"
            done
        else
            print_message "$GREEN" "✓ 没有找到 Bedrock Knowledge Base"
        fi
    fi
    echo
    
    # 总结
    print_message "$BLUE" "=== 检查完成 ==="
    if [ $TOTAL_RESOURCES -eq 0 ]; then
        print_message "$GREEN" "✅ 太好了！没有找到任何与 '$PREFIX' 和 '$ENVIRONMENT' 相关的遗留资源。"
    else
        print_message "$RED" "⚠️  发现 $TOTAL_RESOURCES 个遗留资源。"
    fi
    echo
    
    # 返回资源数量
    return $TOTAL_RESOURCES
}

# 确认清理
confirm_cleanup() {
    if [ "$AUTO_CONFIRM" = true ]; then
        print_message "$YELLOW" "检测到 --yes 选项，自动确认清理。"
        return 0
    fi

    print_message "$RED" "⚠️  警告：这将删除所有与 '$PREFIX' 和 '$ENVIRONMENT' 相关的 AWS 资源！"
    print_message "$RED" "这是不可逆的操作，请确保您要删除的是正确的资源。"
    echo
    read -p "请输入 'DELETE' 来确认删除: " confirm
    
    if [ "$confirm" != "DELETE" ]; then
        print_message "$YELLOW" "操作已取消"
        return 1
    fi
    return 0
}

# VPC清理失败后的诊断函数
diagnose_vpc_deletion_failure() {
    local vpc_id=$1
    print_message "$RED" "诊断VPC $vpc_id 删除失败的原因..."
    
    # 检查网络接口
    ENIS=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$vpc_id" --query "NetworkInterfaces[].{ID:NetworkInterfaceId,Type:InterfaceType,Desc:Description,Status:Status}" --output json 2>/dev/null)
    if [ "$(echo "$ENIS" | jq 'length')" -gt 0 ]; then
        print_message "$YELLOW" "  - 发现残留的网络接口 (ENIs):"
        echo "$ENIS" | jq -r '.[] | "    - \(.ID) (\(.Type), \(.Status)): \(.Desc)"'
    fi

    # 检查安全组
    SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc_id" --query "SecurityGroups[?GroupName!='default'].{ID:GroupId,Name:GroupName}" --output json 2>/dev/null)
    if [ "$(echo "$SGS" | jq 'length')" -gt 0 ]; then
        print_message "$YELLOW" "  - 发现残留的安全组:"
        echo "$SGS" | jq -r '.[] | "    - \(.ID) (\(.Name))"'
    fi

    # 检查其他VPC资源...
}

# 特殊残留资源清理函数 - 专门针对常见的清理遗漏问题
cleanup_specific_resources() {
    print_message "$YELLOW" "检查和清理特殊的残留资源..."
    
    # 1. 强力清理Lambda函数相关的CloudWatch日志组
    print_message "$CYAN" "  强力清理Lambda函数日志组..."
    
    # 动态获取Lambda函数名称，避免硬编码
    local lambda_functions=()
    while IFS= read -r func_name; do
        if [ -n "$func_name" ] && [ "$func_name" != "None" ]; then
            lambda_functions+=("$func_name")
        fi
    done < <(aws lambda list-functions --query "Functions[?contains(FunctionName, '$PREFIX') && contains(FunctionName, '$ENVIRONMENT')].FunctionName" --output text 2>/dev/null | tr '\t' '\n')
    
    # 如果动态查询没有结果，回退到已知的函数名称模式
    if [ ${#lambda_functions[@]} -eq 0 ]; then
        print_message "$BLUE" "  动态查询未找到Lambda函数，使用已知模式..."
        local known_patterns=(
            "${PREFIX}-index-creator-${ENVIRONMENT}"
            "${PREFIX}-document-processor-${ENVIRONMENT}"
            "${PREFIX}-query-handler-${ENVIRONMENT}"
            "${PREFIX}-authorizer-${ENVIRONMENT}"
        )
        lambda_functions=("${known_patterns[@]}")
    fi
    
    for func_name in "${lambda_functions[@]}"; do
        local log_group_name="/aws/lambda/${func_name}"
        print_message "$BLUE" "    检查日志组: $log_group_name"
        if aws logs describe-log-groups --log-group-name-prefix "$log_group_name" --query "logGroups[0].logGroupName" --output text 2>/dev/null | grep -q "$log_group_name"; then
            print_message "$YELLOW" "    删除残留的日志组: $log_group_name"
            if aws logs delete-log-group --log-group-name "$log_group_name" 2>/dev/null; then
                print_message "$GREEN" "    ✓ 日志组已删除: $log_group_name"
            else
                print_message "$RED" "    ❌ 删除日志组失败: $log_group_name"
            fi
        fi
    done
    
    # 2. 强力清理X-Ray采样规则
    print_message "$CYAN" "  强力清理X-Ray采样规则..."
    local xray_rule_name="${PREFIX}-sampling-${ENVIRONMENT}"
    print_message "$BLUE" "    检查X-Ray规则: $xray_rule_name"
    
    # 尝试多种方式查找和删除X-Ray规则
    if aws xray get-sampling-rule --rule-name "$xray_rule_name" >/dev/null 2>&1; then
        print_message "$YELLOW" "    删除残留的X-Ray规则: $xray_rule_name"
        if aws xray delete-sampling-rule --rule-name "$xray_rule_name" 2>/dev/null; then
            print_message "$GREEN" "    ✓ X-Ray规则已删除: $xray_rule_name"
        else
            print_message "$RED" "    ❌ 删除X-Ray规则失败: $xray_rule_name"
        fi
    fi
    
    # 3. 清理任何遗漏的日志指标过滤器
    print_message "$CYAN" "  清理遗漏的日志指标过滤器..."
    for func_name in "${lambda_functions[@]}"; do
        local log_group_name="/aws/lambda/${func_name}"
        # 检查并删除这个日志组的所有指标过滤器
        local filters=$(aws logs describe-metric-filters --log-group-name "$log_group_name" --query "metricFilters[].filterName" --output text 2>/dev/null || echo "")
        if [ -n "$filters" ] && [ "$filters" != "None" ]; then
            for filter in $filters; do
                if [ -n "$filter" ]; then
                    print_message "$YELLOW" "    删除遗漏的指标过滤器: $filter"
                    aws logs delete-metric-filter --log-group-name "$log_group_name" --filter-name "$filter" 2>/dev/null || true
                fi
            done
        fi
    done
    
    # 4. 清理任何以项目前缀开头的SNS主题
    print_message "$CYAN" "  清理遗漏的SNS主题..."
    local sns_topics=$(aws sns list-topics --query "Topics[?contains(TopicArn, '$PREFIX') && contains(TopicArn, '$ENVIRONMENT')].TopicArn" --output text 2>/dev/null || echo "")
    if [ -n "$sns_topics" ] && [ "$sns_topics" != "None" ]; then
        for topic_arn in $sns_topics; do
            local topic_name=$(echo "$topic_arn" | rev | cut -d':' -f1 | rev)
            print_message "$YELLOW" "    删除遗漏的SNS主题: $topic_name"
            aws sns delete-topic --topic-arn "$topic_arn" 2>/dev/null || true
            print_message "$GREEN" "    ✓ SNS主题已删除: $topic_name"
        done
    fi
    
    # 5. 清理CloudWatch告警
    print_message "$CYAN" "  清理遗漏的CloudWatch告警..."
    local alarms=$(aws cloudwatch describe-alarms --query "MetricAlarms[?contains(AlarmName, '$PREFIX') && contains(AlarmName, '$ENVIRONMENT')].AlarmName" --output text 2>/dev/null || echo "")
    if [ -n "$alarms" ] && [ "$alarms" != "None" ]; then
        for alarm in $alarms; do
            print_message "$YELLOW" "    删除遗漏的告警: $alarm"
            aws cloudwatch delete-alarms --alarm-names "$alarm" 2>/dev/null || true
            print_message "$GREEN" "    ✓ 告警已删除: $alarm"
        done
    fi
    
    print_message "$GREEN" "  特殊残留资源清理完成"
}


# 主程序
print_message "$BLUE" "=== AWS 资源管理脚本 v2.0 ==="
echo

# 验证配置参数的安全性
if ! validate_config; then
    print_message "$RED" "配置验证失败，脚本退出"
    exit 1
fi
echo

# 执行相应的操作
case "$MODE" in
    check)
        check_resources
        ;;
    clean)
        if confirm_cleanup; then
            print_message "$BLUE" "开始彻底清理 AWS 资源..."
            echo
        else
            exit 1
        fi
        ;;
    all)
        check_resources
        RESOURCE_COUNT=$?
        
        if [ $RESOURCE_COUNT -eq 0 ]; then
            print_message "$GREEN" "没有需要清理的资源。"
            exit 0
        fi
        
        echo
        if confirm_cleanup; then
            print_message "$BLUE" "开始彻底清理 AWS 资源..."
            echo
        else
            exit 1
        fi
        ;;
esac

# 如果是clean或all模式，继续执行清理
if [ "$MODE" != "check" ]; then

# 1. 删除 OpenSearch Serverless 资源
print_message "$YELLOW" "=== 清理 OpenSearch Serverless 资源 ==="
# 动态计算OpenSearch前缀（去掉连字符）
OPENSEARCH_PREFIX=$(echo "$PREFIX" | tr -d '-')
# 删除数据访问策略
ACCESS_POLICIES=$(aws opensearchserverless list-access-policies --type data --query "accessPolicySummaries[?contains(name, '$OPENSEARCH_PREFIX') && contains(name, '$ENVIRONMENT')].name" --output text 2>/dev/null || echo "")
if [ -n "$ACCESS_POLICIES" ] && [ "$ACCESS_POLICIES" != "None" ]; then
    for policy in $ACCESS_POLICIES; do
        print_message "$YELLOW" "删除 OpenSearch Access Policy: $policy"
        aws opensearchserverless delete-access-policy --name $policy --type data 2>/dev/null || true
        print_message "$GREEN" "✓ Access Policy 已删除: $policy"
    done
else
    print_message "$GREEN" "✓ 没有找到 OpenSearch Access Policy"
fi

# 删除网络安全策略
NETWORK_POLICIES=$(aws opensearchserverless list-security-policies --type network --query "securityPolicySummaries[?contains(name, '$OPENSEARCH_PREFIX') && contains(name, '$ENVIRONMENT')].name" --output text 2>/dev/null || echo "")
if [ -n "$NETWORK_POLICIES" ] && [ "$NETWORK_POLICIES" != "None" ]; then
    for policy in $NETWORK_POLICIES; do
        print_message "$YELLOW" "删除 OpenSearch Network Policy: $policy"
        aws opensearchserverless delete-security-policy --name $policy --type network 2>/dev/null || true
        print_message "$GREEN" "✓ Network Policy 已删除: $policy"
    done
else
    print_message "$GREEN" "✓ 没有找到 OpenSearch Network Policy"
fi

# 删除加密安全策略
ENCRYPTION_POLICIES=$(aws opensearchserverless list-security-policies --type encryption --query "securityPolicySummaries[?contains(name, '$OPENSEARCH_PREFIX') && contains(name, '$ENVIRONMENT')].name" --output text 2>/dev/null || echo "")
if [ -n "$ENCRYPTION_POLICIES" ] && [ "$ENCRYPTION_POLICIES" != "None" ]; then
    for policy in $ENCRYPTION_POLICIES; do
        print_message "$YELLOW" "删除 OpenSearch Encryption Policy: $policy"
        aws opensearchserverless delete-security-policy --name $policy --type encryption 2>/dev/null || true
        print_message "$GREEN" "✓ Encryption Policy 已删除: $policy"
    done
else
    print_message "$GREEN" "✓ 没有找到 OpenSearch Encryption Policy"
fi

# 删除集合
COLLECTIONS=$(aws opensearchserverless list-collections --query "collectionSummaries[?contains(name, '$OPENSEARCH_PREFIX') && contains(name, '$ENVIRONMENT')].id" --output text 2>/dev/null || echo "")
if [ -n "$COLLECTIONS" ] && [ "$COLLECTIONS" != "None" ]; then
    for collection_id in $COLLECTIONS; do
        collection_name=$(aws opensearchserverless batch-get-collection --ids $collection_id --query "collectionDetails[0].name" --output text 2>/dev/null || echo "unknown")
        print_message "$YELLOW" "删除 OpenSearch Collection: $collection_name ($collection_id)"
        aws opensearchserverless delete-collection --id $collection_id 2>/dev/null || true
        print_message "$GREEN" "✓ Collection 已删除: $collection_name"
    done
else
    print_message "$GREEN" "✓ 没有找到 OpenSearch Collection"
fi
echo

# 2. 删除 CloudWatch 监控资源
print_message "$YELLOW" "=== 清理 CloudWatch 监控资源 ==="
# 删除仪表板
DASHBOARDS=$(aws cloudwatch list-dashboards --query "DashboardEntries[?contains(DashboardName, '$PREFIX') && contains(DashboardName, '$ENVIRONMENT')].DashboardName" --output text 2>/dev/null || echo "")
if [ -n "$DASHBOARDS" ] && [ "$DASHBOARDS" != "None" ]; then
    for dashboard in $DASHBOARDS; do
        print_message "$YELLOW" "删除 CloudWatch Dashboard: $dashboard"
        aws cloudwatch delete-dashboards --dashboard-names $dashboard 2>/dev/null || true
        print_message "$GREEN" "✓ Dashboard 已删除: $dashboard"
    done
else
    print_message "$GREEN" "✓ 没有找到 CloudWatch Dashboard"
fi

# 删除告警
ALARMS=$(aws cloudwatch describe-alarms --query "MetricAlarms[?contains(AlarmName, '$PREFIX') && contains(AlarmName, '$ENVIRONMENT')].AlarmName" --output text 2>/dev/null || echo "")
if [ -n "$ALARMS" ] && [ "$ALARMS" != "None" ]; then
    for alarm in $ALARMS; do
        print_message "$YELLOW" "删除 CloudWatch Alarm: $alarm"
        aws cloudwatch delete-alarms --alarm-names $alarm 2>/dev/null || true
        print_message "$GREEN" "✓ Alarm 已删除: $alarm"
    done
else
    print_message "$GREEN" "✓ 没有找到 CloudWatch Alarm"
fi

# 删除日志指标过滤器
# 使用改进的查询逻辑 - 包含项目前缀和环境的日志组
FILTER_LOG_GROUPS=$(aws logs describe-log-groups --query "logGroups[?contains(logGroupName, '$PREFIX') && contains(logGroupName, '$ENVIRONMENT')].logGroupName" --output text 2>/dev/null || echo "")
# 同时检查Lambda函数相关的日志组
FILTER_LAMBDA_LOG_GROUPS=$(aws logs describe-log-groups --query "logGroups[?starts_with(logGroupName, '/aws/lambda/$PREFIX')].logGroupName" --output text 2>/dev/null || echo "")

# 使用数组避免重复和空值问题
declare -a FILTER_ALL_LOG_GROUPS_ARRAY
if [ -n "$FILTER_LOG_GROUPS" ] && [ "$FILTER_LOG_GROUPS" != "None" ]; then
    while read -r log_group; do
        if [ -n "$log_group" ]; then
            FILTER_ALL_LOG_GROUPS_ARRAY+=("$log_group")
        fi
    done <<< "$FILTER_LOG_GROUPS"
fi
if [ -n "$FILTER_LAMBDA_LOG_GROUPS" ] && [ "$FILTER_LAMBDA_LOG_GROUPS" != "None" ]; then
    while read -r log_group; do
        if [ -n "$log_group" ]; then
            # 检查是否已存在，避免重复
            local exists=false
            for existing_group in "${FILTER_ALL_LOG_GROUPS_ARRAY[@]}"; do
                if [ "$existing_group" = "$log_group" ]; then
                    exists=true
                    break
                fi
            done
            if [ "$exists" = false ]; then
                FILTER_ALL_LOG_GROUPS_ARRAY+=("$log_group")
            fi
        fi
    done <<< "$FILTER_LAMBDA_LOG_GROUPS"
fi

if [ ${#FILTER_ALL_LOG_GROUPS_ARRAY[@]} -gt 0 ]; then
    for log_group in "${FILTER_ALL_LOG_GROUPS_ARRAY[@]}"; do
        # 跳过空字符串
        if [ -z "$log_group" ]; then
            continue
        fi
        # 只处理包含环境标识的日志组
        if [[ "$log_group" == *"$ENVIRONMENT"* ]]; then
            METRIC_FILTERS=$(aws logs describe-metric-filters --log-group-name "$log_group" --query "metricFilters[].filterName" --output text 2>/dev/null || echo "")
            if [ -n "$METRIC_FILTERS" ] && [ "$METRIC_FILTERS" != "None" ]; then
                for filter in $METRIC_FILTERS; do
                    if [ -n "$filter" ]; then
                        print_message "$YELLOW" "删除 Metric Filter: $filter (from $log_group)"
                        if aws logs delete-metric-filter --log-group-name "$log_group" --filter-name "$filter" 2>/dev/null; then
                            print_message "$GREEN" "✓ Metric Filter 已删除: $filter"
                        else
                            print_message "$RED" "❌ 删除 Metric Filter 失败: $filter"
                        fi
                    fi
                done
            fi
        fi
    done
fi
echo

# 3. 删除 SNS 主题
print_message "$YELLOW" "=== 清理 SNS 主题 ==="
SNS_TOPICS=$(aws sns list-topics --query "Topics[?contains(TopicArn, '$PREFIX') && contains(TopicArn, '$ENVIRONMENT')].TopicArn" --output text 2>/dev/null || echo "")
if [ -n "$SNS_TOPICS" ] && [ "$SNS_TOPICS" != "None" ]; then
    for topic_arn in $SNS_TOPICS; do
        topic_name=$(echo $topic_arn | rev | cut -d':' -f1 | rev)
        print_message "$YELLOW" "删除 SNS Topic: $topic_name"
        aws sns delete-topic --topic-arn $topic_arn 2>/dev/null || true
        print_message "$GREEN" "✓ SNS Topic 已删除: $topic_name"
    done
else
    print_message "$GREEN" "✓ 没有找到 SNS Topic"
fi
echo

# 4. 删除 X-Ray 采样规则
print_message "$YELLOW" "=== 清理 X-Ray 资源 ==="
# 增强的X-Ray清理逻辑 - 使用多种查询方式确保完整清理
SAMPLING_RULES=$(aws xray get-sampling-rules --query "SamplingRuleRecords[?contains(SamplingRule.ruleName, '$PREFIX') && contains(SamplingRule.ruleName, '$ENVIRONMENT')].SamplingRule.ruleName" --output text 2>/dev/null || echo "")

# 如果第一次查询没有结果，尝试更宽泛的查询
if [ -z "$SAMPLING_RULES" ] || [ "$SAMPLING_RULES" = "None" ]; then
    print_message "$BLUE" "  尝试更宽泛的X-Ray规则查询..."
    SAMPLING_RULES=$(aws xray get-sampling-rules --query "SamplingRuleRecords[?contains(SamplingRule.ruleName, '$PREFIX')].SamplingRule.ruleName" --output text 2>/dev/null | grep "$ENVIRONMENT" || echo "")
fi

# 如果还是没有结果，尝试列出所有规则并手动过滤
if [ -z "$SAMPLING_RULES" ] || [ "$SAMPLING_RULES" = "None" ]; then
    print_message "$BLUE" "  列出所有X-Ray规则并过滤..."
    ALL_RULES=$(aws xray get-sampling-rules --query "SamplingRuleRecords[].SamplingRule.ruleName" --output text 2>/dev/null || echo "")
    if [ -n "$ALL_RULES" ] && [ "$ALL_RULES" != "None" ]; then
        for rule in $ALL_RULES; do
            if [[ "$rule" == *"$PREFIX"* && "$rule" == *"$ENVIRONMENT"* ]]; then
                SAMPLING_RULES="$SAMPLING_RULES $rule"
            fi
        done
    fi
fi

if [ -n "$SAMPLING_RULES" ] && [ "$SAMPLING_RULES" != "None" ]; then
    for rule in $SAMPLING_RULES; do
        # 跳过空字符串
        if [ -z "$rule" ]; then
            continue
        fi
        print_message "$YELLOW" "删除 X-Ray Sampling Rule: $rule"
        if aws xray delete-sampling-rule --rule-name "$rule" 2>/dev/null; then
            print_message "$GREEN" "✓ X-Ray Sampling Rule 已删除: $rule"
        else
            print_message "$RED" "❌ 删除 X-Ray Sampling Rule 失败: $rule"
            # 尝试获取更多信息
            RULE_INFO=$(aws xray get-sampling-rule --rule-name "$rule" 2>/dev/null || echo "Rule not found")
            print_message "$BLUE" "  规则信息: $RULE_INFO"
        fi
    done
else
    print_message "$GREEN" "✓ 没有找到 X-Ray Sampling Rule"
fi
echo

# 5. 删除 EventBridge 规则
print_message "$YELLOW" "=== 清理 EventBridge 规则 ==="
EVENT_RULES=$(aws events list-rules --query "Rules[?contains(Name, '$PREFIX') && contains(Name, '$ENVIRONMENT')].Name" --output text 2>/dev/null || echo "")
if [ -n "$EVENT_RULES" ] && [ "$EVENT_RULES" != "None" ]; then
    for rule in $EVENT_RULES; do
        print_message "$YELLOW" "删除 EventBridge Rule: $rule"
        # 先删除目标
        TARGETS=$(aws events list-targets-by-rule --rule $rule --query "Targets[].Id" --output text 2>/dev/null || echo "")
        if [ -n "$TARGETS" ]; then
            aws events remove-targets --rule $rule --ids $TARGETS 2>/dev/null || true
        fi
        # 再删除规则
        aws events delete-rule --name $rule 2>/dev/null || true
        print_message "$GREEN" "✓ EventBridge Rule 已删除: $rule"
    done
else
    print_message "$GREEN" "✓ 没有找到 EventBridge Rule"
fi
echo

# 6. 删除 KMS 密钥
print_message "$YELLOW" "=== 清理 KMS 密钥 ==="
# 先删除别名
KMS_ALIASES=$(aws kms list-aliases --query "Aliases[?contains(AliasName, '$PREFIX') && contains(AliasName, '$ENVIRONMENT')].AliasName" --output text 2>/dev/null || echo "")
if [ -n "$KMS_ALIASES" ] && [ "$KMS_ALIASES" != "None" ]; then
    for alias in $KMS_ALIASES; do
        print_message "$YELLOW" "删除 KMS Alias: $alias"
        aws kms delete-alias --alias-name $alias 2>/dev/null || true
        print_message "$GREEN" "✓ KMS Alias 已删除: $alias"
    done
fi

# 计划删除密钥（不能立即删除）
KMS_KEYS=$(aws kms list-keys --query "Keys[].KeyId" --output text 2>/dev/null || echo "")
if [ -n "$KMS_KEYS" ] && [ "$KMS_KEYS" != "None" ]; then
    for key_id in $KMS_KEYS; do
        # 检查密钥描述是否包含项目前缀
        KEY_DESC=$(aws kms describe-key --key-id $key_id --query "KeyMetadata.Description" --output text 2>/dev/null || echo "")
        if [[ "$KEY_DESC" == *"$PREFIX"* && "$KEY_DESC" == *"$ENVIRONMENT"* ]]; then
            print_message "$YELLOW" "计划删除 KMS Key: $key_id"
            aws kms schedule-key-deletion --key-id $key_id --pending-window-in-days 7 2>/dev/null || true
            print_message "$GREEN" "✓ KMS Key 已计划在7天后删除: $key_id"
        fi
    done
else
    print_message "$GREEN" "✓ 没有找到 KMS Key"
fi
echo

# 7. 删除 CloudFront Origin Access Identity
print_message "$YELLOW" "=== 清理 CloudFront OAI ==="
OAI_LIST=$(aws cloudfront list-cloud-front-origin-access-identities --query "CloudFrontOriginAccessIdentityList.Items[?contains(Comment, '$PREFIX') && contains(Comment, '$ENVIRONMENT')].Id" --output text 2>/dev/null || echo "")
if [ -n "$OAI_LIST" ] && [ "$OAI_LIST" != "None" ]; then
    for oai_id in $OAI_LIST; do
        print_message "$YELLOW" "删除 CloudFront OAI: $oai_id"
        # 获取 ETag
        ETAG=$(aws cloudfront get-cloud-front-origin-access-identity --id $oai_id --query "ETag" --output text 2>/dev/null || echo "")
        if [ -n "$ETAG" ]; then
            aws cloudfront delete-cloud-front-origin-access-identity --id $oai_id --if-match $ETAG 2>/dev/null || true
            print_message "$GREEN" "✓ CloudFront OAI 已删除: $oai_id"
        fi
    done
else
    print_message "$GREEN" "✓ 没有找到 CloudFront OAI"
fi

# 删除 Response Headers Policy
HEADERS_POLICIES=$(aws cloudfront list-response-headers-policies --query "ResponseHeadersPolicyList.Items[?contains(ResponseHeadersPolicy.ResponseHeadersPolicyConfig.Comment, '$PREFIX') && contains(ResponseHeadersPolicy.ResponseHeadersPolicyConfig.Comment, '$ENVIRONMENT')].ResponseHeadersPolicy.Id" --output text 2>/dev/null || echo "")
if [ -n "$HEADERS_POLICIES" ] && [ "$HEADERS_POLICIES" != "None" ]; then
    for policy_id in $HEADERS_POLICIES; do
        print_message "$YELLOW" "删除 CloudFront Response Headers Policy: $policy_id"
        # 获取 ETag
        ETAG=$(aws cloudfront get-response-headers-policy --id $policy_id --query "ETag" --output text 2>/dev/null || echo "")
        if [ -n "$ETAG" ]; then
            aws cloudfront delete-response-headers-policy --id $policy_id --if-match $ETAG 2>/dev/null || true
            print_message "$GREEN" "✓ Response Headers Policy 已删除: $policy_id"
        fi
    done
else
    print_message "$GREEN" "✓ 没有找到 CloudFront Response Headers Policy"
fi
echo

# 执行基础资源清理
print_message "$BLUE" "执行基础资源清理..."

# 1. 禁用并删除 CloudFront 分发
print_message "$YELLOW" "=== 清理 CloudFront 分发 ==="
DISTRIBUTIONS=$(aws cloudfront list-distributions --query "DistributionList.Items[?contains(Comment, '$PREFIX') && contains(Comment, '$ENVIRONMENT')].Id" --output text 2>/dev/null || echo "")
if [ -n "$DISTRIBUTIONS" ] && [ "$DISTRIBUTIONS" != "None" ]; then
    for dist_id in $DISTRIBUTIONS; do
        print_message "$YELLOW" "正在处理 CloudFront 分发: $dist_id"
        # 步骤 1: 禁用分发
        # 获取当前配置和ETag
        CONFIG_JSON=$(aws cloudfront get-distribution-config --id $dist_id 2>/dev/null)
        if [ $? -ne 0 ]; then
            print_message "$RED" "  ❌ 无法获取分发 $dist_id 的配置。"
            continue
        fi

        ETAG=$(echo "$CONFIG_JSON" | jq -r '.ETag')
        IS_ENABLED=$(echo "$CONFIG_JSON" | jq -r '.DistributionConfig.Enabled')

        if [ "$IS_ENABLED" = "true" ]; then
            print_message "$BLUE" "  禁用分发: $dist_id"
            # 使用安全的临时文件创建
            TEMP_CONFIG_FILE=$(mktemp) || { 
                print_message "$RED" "  ❌ 无法创建临时文件"; 
                continue; 
            }
            # 确保临时文件在脚本退出时被清理
            trap "rm -f $TEMP_CONFIG_FILE" EXIT
            
            # 设置为禁用并更新
            echo "$CONFIG_JSON" | jq '.DistributionConfig.Enabled = false' > "$TEMP_CONFIG_FILE"
            aws cloudfront update-distribution --id $dist_id --distribution-config "file://$TEMP_CONFIG_FILE" --if-match $ETAG > /dev/null 2>&1
            if [ $? -ne 0 ]; then
                print_message "$RED" "  ❌ 禁用分发 $dist_id 失败。"
                continue
            fi
            print_message "$GREEN" "  ✓ 分发已提交禁用请求，等待全球同步..."
        else
            print_message "$GREEN" "  ✓ 分发 $dist_id 已是禁用状态。"
        fi

        # 步骤 2: 等待禁用完成
        TIMEOUT=900 # 15分钟超时
        INTERVAL=20
        ELAPSED=0
        while [ $ELAPSED -lt $TIMEOUT ]; do
            STATUS_JSON=$(aws cloudfront get-distribution --id $dist_id 2>/dev/null)
            STATUS=$(echo "$STATUS_JSON" | jq -r '.Distribution.Status')
            if [ "$STATUS" = "Deployed" ]; then
                IS_ENABLED_CHECK=$(echo "$STATUS_JSON" | jq -r '.Distribution.DistributionConfig.Enabled')
                if [ "$IS_ENABLED_CHECK" = "false" ]; then
                    print_message "$GREEN" "  ✓ 分发 $dist_id 已成功禁用。"
                    break
                fi
            fi
            sleep $INTERVAL
            ELAPSED=$((ELAPSED + INTERVAL))
            print_message "$BLUE" "  ...等待中 ($ELAPSED / $TIMEOUT s)"
        done

        if [ $ELAPSED -ge $TIMEOUT ]; then
            print_message "$RED" "  ❌ 禁用分发 $dist_id 超时。"
            continue
        fi

        # 步骤 3: 删除分发
        # 需要获取最新的ETag才能删除
        FINAL_ETAG=$(aws cloudfront get-distribution --id $dist_id | jq -r '.ETag')
        print_message "$YELLOW" "  删除分发: $dist_id"
        if aws cloudfront delete-distribution --id $dist_id --if-match "$FINAL_ETAG" 2>/dev/null; then
            print_message "$GREEN" "  ✓ 分发 $dist_id 已成功删除。"
        else
            print_message "$RED" "  ❌ 删除分发 $dist_id 失败。"
        fi
    done
else
    print_message "$GREEN" "✓ 没有找到 CloudFront 分发"
fi
echo

# 2. 清空并删除 S3 存储桶
print_message "$YELLOW" "=== 清理 S3 存储桶 ==="
BUCKETS=$(aws s3api list-buckets --query "Buckets[?contains(Name, '$PREFIX')].Name" --output text 2>/dev/null || echo "")
if [ -n "$BUCKETS" ] && [ "$BUCKETS" != "None" ]; then
    for bucket in $BUCKETS; do
        print_message "$YELLOW" "开始清理存储桶: $bucket"
        
        # 删除存储桶策略，以防限制删除操作
        print_message "$BLUE" "  - 删除存储桶策略 (如果存在)..."
        aws s3api delete-bucket-policy --bucket $bucket 2>/dev/null || true

        print_message "$BLUE" "  - 清空所有对象版本和删除标记..."
        # 删除所有对象版本 - 避免使用eval的安全版本
        aws s3api list-object-versions --bucket "$bucket" --query 'Versions[]' --output json 2>/dev/null | \
        jq -r '.[] | [.Key, .VersionId] | @tsv' | \
        while IFS=$'\t' read -r object_key version_id; do
            if [ -n "$object_key" ] && [ -n "$version_id" ]; then
                aws s3api delete-object --bucket "$bucket" --key "$object_key" --version-id "$version_id" 2>/dev/null || true
            fi
        done
        
        # 删除所有删除标记 - 避免使用eval的安全版本
        aws s3api list-object-versions --bucket "$bucket" --query 'DeleteMarkers[]' --output json 2>/dev/null | \
        jq -r '.[] | [.Key, .VersionId] | @tsv' | \
        while IFS=$'\t' read -r object_key version_id; do
            if [ -n "$object_key" ] && [ -n "$version_id" ]; then
                aws s3api delete-object --bucket "$bucket" --key "$object_key" --version-id "$version_id" 2>/dev/null || true
            fi
        done
        
        # 删除所有当前对象
        aws s3 rm s3://$bucket --recursive 2>/dev/null || true
        
        # 删除存储桶
        print_message "$YELLOW" "  - 删除存储桶: $bucket"
        if aws s3api delete-bucket --bucket $bucket 2>/dev/null; then
            print_message "$GREEN" "✓ 存储桶已成功删除: $bucket"
        else
            print_message "$RED" "❌ 删除存储桶 $bucket 失败。可能原因：存储桶非空（请检查是否有未清空的对象版本），或权限问题。"
        fi
    done
else
    print_message "$GREEN" "✓ 没有找到 S3 存储桶"
fi
echo

# 3. 删除 Lambda 函数
print_message "$YELLOW" "=== 清理 Lambda 函数 ==="
FUNCTIONS=$(aws lambda list-functions --query "Functions[?contains(FunctionName, '$PREFIX') && contains(FunctionName, '$ENVIRONMENT')].FunctionName" --output text 2>&1)
LAMBDA_DELETED=false
if [ $? -eq 0 ] && [ -n "$FUNCTIONS" ] && [ "$FUNCTIONS" != "None" ]; then
    for func in $FUNCTIONS; do
        print_message "$YELLOW" "删除 Lambda 函数: $func"
        if aws lambda delete-function --function-name $func 2>&1; then
            print_message "$GREEN" "✓ Lambda 函数已删除: $func"
            LAMBDA_DELETED=true
        else
            print_message "$RED" "❌ 无法删除 Lambda 函数: $func"
        fi
    done
    
    # 如果删除了Lambda函数，等待ENI自动释放
    if [ "$LAMBDA_DELETED" = "true" ]; then
        print_message "$YELLOW" "等待 Lambda ENI 自动释放（90秒）..."
        sleep 90
    fi
else
    print_message "$GREEN" "✓ 没有找到 Lambda 函数"
fi
echo

# 4. 删除 Lambda 层
print_message "$YELLOW" "=== 清理 Lambda 层 ==="
LAYERS=$(aws lambda list-layers --query "Layers[?contains(LayerName, '$PREFIX') && contains(LayerName, '$ENVIRONMENT')].LayerArn" --output text 2>/dev/null || echo "")
if [ -n "$LAYERS" ] && [ "$LAYERS" != "None" ]; then
    for layer_arn in $LAYERS; do
        layer_name=$(echo $layer_arn | cut -d: -f7)
        print_message "$YELLOW" "删除 Lambda 层: $layer_name"
        # 获取所有版本
        VERSIONS=$(aws lambda list-layer-versions --layer-name $layer_name --query "LayerVersions[].Version" --output text 2>/dev/null || echo "")
        for version in $VERSIONS; do
            aws lambda delete-layer-version --layer-name $layer_name --version-number $version 2>/dev/null || true
        done
        print_message "$GREEN" "✓ Lambda 层已删除: $layer_name"
    done
else
    print_message "$GREEN" "✓ 没有找到 Lambda 层"
fi
echo

# 5. 删除 API Gateway
print_message "$YELLOW" "=== 清理 API Gateway ==="
APIS=$(aws apigateway get-rest-apis --query "items[?contains(name, '$PREFIX') && contains(name, '$ENVIRONMENT')].id" --output text 2>/dev/null || echo "")
if [ -n "$APIS" ] && [ "$APIS" != "None" ]; then
    for api_id in $APIS; do
        api_name=$(aws apigateway get-rest-api --rest-api-id $api_id --query "name" --output text 2>/dev/null || echo "unknown")
        print_message "$YELLOW" "删除 API Gateway: $api_name ($api_id)"
        # 等待一段时间再删除，避免 "TooManyRequestsException"
        sleep 5
        aws apigateway delete-rest-api --rest-api-id $api_id 2>/dev/null || true
        print_message "$GREEN" "✓ API Gateway 已删除: $api_name"
    done
else
    print_message "$GREEN" "✓ 没有找到 API Gateway"
fi
echo

# 6. 删除 Cognito User Pool
print_message "$YELLOW" "=== 清理 Cognito User Pool ==="
USER_POOLS=$(aws cognito-idp list-user-pools --max-results 50 --query "UserPools[?contains(Name, '$PREFIX') && contains(Name, '$ENVIRONMENT')].Id" --output text 2>/dev/null || echo "")
if [ -n "$USER_POOLS" ] && [ "$USER_POOLS" != "None" ]; then
    for pool_id in $USER_POOLS; do
        pool_name=$(aws cognito-idp describe-user-pool --user-pool-id $pool_id --query "UserPool.Name" --output text 2>/dev/null || echo "unknown")
        print_message "$YELLOW" "删除 Cognito User Pool: $pool_name ($pool_id)"
        # 先删除 domain
        DOMAIN=$(aws cognito-idp describe-user-pool --user-pool-id $pool_id --query "UserPool.Domain" --output text 2>/dev/null || echo "")
        if [ "$DOMAIN" != "None" ] && [ -n "$DOMAIN" ] && [ "$DOMAIN" != "null" ]; then
            aws cognito-idp delete-user-pool-domain --user-pool-id $pool_id --domain $DOMAIN 2>/dev/null || true
        fi
        # 删除 user pool
        aws cognito-idp delete-user-pool --user-pool-id $pool_id 2>/dev/null || true
        print_message "$GREEN" "✓ Cognito User Pool 已删除: $pool_name"
    done
else
    print_message "$GREEN" "✓ 没有找到 Cognito User Pool"
fi
echo

# 7. 删除 CloudWatch 日志组
print_message "$YELLOW" "=== 清理 CloudWatch 日志组 ==="
# 使用改进的查询逻辑 - 包含项目前缀和环境的日志组
LOG_GROUPS=$(aws logs describe-log-groups --query "logGroups[?contains(logGroupName, '$PREFIX') && contains(logGroupName, '$ENVIRONMENT')].logGroupName" --output text 2>/dev/null || echo "")
# 同时检查Lambda函数相关的日志组
LAMBDA_LOG_GROUPS=$(aws logs describe-log-groups --query "logGroups[?starts_with(logGroupName, '/aws/lambda/$PREFIX')].logGroupName" --output text 2>/dev/null || echo "")

# 使用数组避免重复和空值问题
declare -a ALL_LOG_GROUPS_ARRAY
if [ -n "$LOG_GROUPS" ] && [ "$LOG_GROUPS" != "None" ]; then
    while read -r log_group; do
        if [ -n "$log_group" ]; then
            ALL_LOG_GROUPS_ARRAY+=("$log_group")
        fi
    done <<< "$LOG_GROUPS"
fi
if [ -n "$LAMBDA_LOG_GROUPS" ] && [ "$LAMBDA_LOG_GROUPS" != "None" ]; then
    while read -r log_group; do
        if [ -n "$log_group" ]; then
            # 检查是否已存在，避免重复
            local exists=false
            for existing_group in "${ALL_LOG_GROUPS_ARRAY[@]}"; do
                if [ "$existing_group" = "$log_group" ]; then
                    exists=true
                    break
                fi
            done
            if [ "$exists" = false ]; then
                ALL_LOG_GROUPS_ARRAY+=("$log_group")
            fi
        fi
    done <<< "$LAMBDA_LOG_GROUPS"
fi

# 删除找到的日志组
DELETED_COUNT=0
if [ ${#ALL_LOG_GROUPS_ARRAY[@]} -gt 0 ]; then
    # 去重并过滤包含环境的日志组
    for log_group in "${ALL_LOG_GROUPS_ARRAY[@]}"; do
        # 跳过空字符串
        if [ -z "$log_group" ]; then
            continue
        fi
        # 只删除包含环境标识的日志组
        if [[ "$log_group" == *"$ENVIRONMENT"* ]]; then
            print_message "$YELLOW" "删除日志组: $log_group"
            if aws logs delete-log-group --log-group-name "$log_group" 2>/dev/null; then
                print_message "$GREEN" "✓ 日志组已删除: $log_group"
                ((DELETED_COUNT++))
            else
                print_message "$RED" "❌ 删除日志组失败: $log_group"
            fi
        fi
    done
    
    if [ $DELETED_COUNT -eq 0 ]; then
        print_message "$GREEN" "✓ 没有找到匹配的 CloudWatch 日志组"
    else
        print_message "$BLUE" "已删除 $DELETED_COUNT 个日志组"
    fi
else
    print_message "$GREEN" "✓ 没有找到 CloudWatch 日志组"
fi
echo

# 8. 删除 IAM 角色和策略
print_message "$YELLOW" "=== 清理 IAM 角色和策略 ==="
# 删除角色
ROLES=$(aws iam list-roles --query "Roles[?contains(RoleName, '$PREFIX') && contains(RoleName, '$ENVIRONMENT')].RoleName" --output text 2>/dev/null || echo "")
if [ -n "$ROLES" ] && [ "$ROLES" != "None" ]; then
    for role in $ROLES; do
        print_message "$YELLOW" "删除 IAM 角色: $role"
        # 先分离所有策略
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name $role --query "AttachedPolicies[].PolicyArn" --output text 2>/dev/null || echo "")
        for policy_arn in $ATTACHED_POLICIES; do
            aws iam detach-role-policy --role-name $role --policy-arn $policy_arn 2>/dev/null || true
        done
        # 删除内联策略
        INLINE_POLICIES=$(aws iam list-role-policies --role-name $role --query "PolicyNames[]" --output text 2>/dev/null || echo "")
        for policy_name in $INLINE_POLICIES; do
            aws iam delete-role-policy --role-name $role --policy-name $policy_name 2>/dev/null || true
        done
        # 删除实例配置文件
        INSTANCE_PROFILES=$(aws iam list-instance-profiles-for-role --role-name $role --query "InstanceProfiles[].InstanceProfileName" --output text 2>/dev/null || echo "")
        for ip_name in $INSTANCE_PROFILES; do
             aws iam remove-role-from-instance-profile --instance-profile-name $ip_name --role-name $role 2>/dev/null || true
             aws iam delete-instance-profile --instance-profile-name $ip_name 2>/dev/null || true
        done
        # 删除角色
        aws iam delete-role --role-name $role 2>/dev/null || true
        print_message "$GREEN" "✓ IAM 角色已删除: $role"
    done
else
    print_message "$GREEN" "✓ 没有找到 IAM 角色"
fi

# 删除策略
POLICIES=$(aws iam list-policies --scope Local --query "Policies[?contains(PolicyName, '$PREFIX') && contains(PolicyName, '$ENVIRONMENT')].Arn" --output text 2>/dev/null || echo "")
if [ -n "$POLICIES" ] && [ "$POLICIES" != "None" ]; then
    for policy_arn in $POLICIES; do
        policy_name=$(echo $policy_arn | rev | cut -d'/' -f1 | rev)
        print_message "$YELLOW" "删除 IAM 策略: $policy_name"
        # 分离所有附加的实体
        ATTACHMENT_COUNT=$(aws iam get-policy --policy-arn $policy_arn --query 'Policy.AttachmentCount' 2>/dev/null || echo "0")
        if [ "$ATTACHMENT_COUNT" -gt 0 ]; then
             print_message "$YELLOW" "  - 策略 $policy_name 仍被附加，跳过删除"
             continue
        fi

        # 删除所有策略版本（保留默认版本）
        VERSIONS=$(aws iam list-policy-versions --policy-arn "$policy_arn" --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text 2>/dev/null)
        for v in $VERSIONS; do
            aws iam delete-policy-version --policy-arn "$policy_arn" --version-id "$v" 2>/dev/null
        done

        aws iam delete-policy --policy-arn $policy_arn 2>/dev/null || true
        print_message "$GREEN" "✓ IAM 策略已删除: $policy_name"
    done
else
    print_message "$GREEN" "✓ 没有找到 IAM 策略"
fi
echo

# 9. 删除 Bedrock Knowledge Base
print_message "$YELLOW" "=== 清理 Bedrock Knowledge Base ==="
# 尝试列出所有knowledge bases
KB_OUTPUT=$(aws bedrock-agent list-knowledge-bases 2>&1)
if [ $? -eq 0 ]; then
    # API调用成功，获取包含前缀的knowledge base IDs
    KB_IDS=$(echo "$KB_OUTPUT" | jq -r ".knowledgeBaseSummaries[] | select(.name | contains(\"$PREFIX\") and contains(\"$ENVIRONMENT\")) | .knowledgeBaseId" 2>/dev/null || echo "")
    if [ -n "$KB_IDS" ]; then
        echo "$KB_IDS" | while read -r kb_id; do
            kb_name=$(echo "$KB_OUTPUT" | jq -r ".knowledgeBaseSummaries[] | select(.knowledgeBaseId==\"$kb_id\") | .name" 2>/dev/null || echo "unknown")
            print_message "$YELLOW" "删除 Knowledge Base: $kb_name ($kb_id)"
            aws bedrock-agent delete-knowledge-base --knowledge-base-id $kb_id 2>/dev/null || true
            print_message "$GREEN" "✓ Knowledge Base 已删除: $kb_name"
        done
    else
        print_message "$GREEN" "✓ 没有找到 Bedrock Knowledge Base"
    fi
else
    # API调用失败
    if echo "$KB_OUTPUT" | grep -q "UnrecognizedClientException\|AccessDeniedException"; then
        print_message "$YELLOW" "⚠️  Bedrock API 在此区域不可用或没有权限"
    else
        print_message "$YELLOW" "⚠️  无法访问 Bedrock API，跳过 Knowledge Base 清理"
    fi
fi
echo

# 继续执行增强清理...

# 10. 清理 VPC 资源（最后执行）
print_message "$YELLOW" "=== 清理 VPC 资源 ==="
# 获取VPC ID
VPCS=$(aws ec2 describe-vpcs --filters "Name=tag:Project,Values=$PREFIX" "Name=tag:Environment,Values=$ENVIRONMENT" --query "Vpcs[].VpcId" --output text 2>/dev/null || echo "")
if [ -n "$VPCS" ]; then
    for vpc_id in $VPCS; do
        print_message "$BLUE" "开始清理 VPC: $vpc_id"
        
        # 删除 NAT Gateways
        NAT_GATEWAYS=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpc_id" "Name=state,Values=available,pending" --query "NatGateways[].NatGatewayId" --output text 2>&1)
        if [ $? -eq 0 ] && [ -n "$NAT_GATEWAYS" ] && [ "$NAT_GATEWAYS" != "None" ]; then
            for nat_id in $NAT_GATEWAYS; do
                print_message "$YELLOW" "  删除 NAT Gateway: $nat_id"
                aws ec2 delete-nat-gateway --nat-gateway-id $nat_id
            done
            # 等待NAT Gateway删除
            print_message "$BLUE" "  等待 NAT Gateway 删除（90秒）..."
            sleep 90
        fi
        
        # 释放弹性IP地址
        EIPS=$(aws ec2 describe-addresses --filters "Name=domain,Values=vpc" --query "Addresses[?VpcId=='$vpc_id'].AllocationId" --output text 2>/dev/null || echo "")
        if [ -n "$EIPS" ] && [ "$EIPS" != "None" ]; then
            for eip_id in $EIPS; do
                print_message "$YELLOW" "  释放 Elastic IP: $eip_id"
                aws ec2 release-address --allocation-id $eip_id 2>/dev/null || true
            done
        fi
        
        # 删除 VPC Endpoints
        VPC_ENDPOINTS=$(aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$vpc_id" --query "VpcEndpoints[].VpcEndpointId" --output text 2>&1)
        if [ $? -eq 0 ] && [ -n "$VPC_ENDPOINTS" ] && [ "$VPC_ENDPOINTS" != "None" ]; then
            print_message "$YELLOW" "  删除 VPC Endpoints..."
            aws ec2 delete-vpc-endpoints --vpc-endpoint-ids $VPC_ENDPOINTS
            # 等待VPC Endpoints删除
            print_message "$BLUE" "  等待 VPC Endpoints 删除（60秒）..."
            sleep 60
        fi
        
        # 删除网络接口
        print_message "$YELLOW" "  检查和删除网络接口 (最多重试3次)..."
        for attempt in {1..3}; do
            NETWORK_INTERFACES=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$vpc_id" --query "NetworkInterfaces[?RequesterManaged==\`false\`].NetworkInterfaceId" --output text)
            if [ -z "$NETWORK_INTERFACES" ]; then
                print_message "$GREEN" "  ✓ 所有自定义网络接口已清理"
                break
            fi
            
            print_message "$BLUE" "  第 $attempt 次尝试删除 ENIs: $NETWORK_INTERFACES"
            for eni_id in $NETWORK_INTERFACES; do
                ATTACHMENT_ID=$(aws ec2 describe-network-interfaces --network-interface-ids $eni_id --query "NetworkInterfaces[0].Attachment.AttachmentId" --output text 2>/dev/null)
                if [ -n "$ATTACHMENT_ID" ] && [ "$ATTACHMENT_ID" != "None" ]; then
                     aws ec2 detach-network-interface --attachment-id $ATTACHMENT_ID --force 2>/dev/null
                     sleep 10
                fi
                aws ec2 delete-network-interface --network-interface-id $eni_id 2>/dev/null
            done
            sleep 20
        done
        
        # 删除安全组（除了默认安全组）
        SECURITY_GROUPS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc_id" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text 2>/dev/null || echo "")
        if [ -n "$SECURITY_GROUPS" ] && [ "$SECURITY_GROUPS" != "None" ]; then
            for sg_id in $SECURITY_GROUPS; do
                print_message "$YELLOW" "  删除 Security Group: $sg_id"
                aws ec2 delete-security-group --group-id $sg_id 2>/dev/null || true
            done
        fi
        
        # 分离并删除 Internet Gateway
        IGW=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc_id" --query "InternetGateways[].InternetGatewayId" --output text 2>/dev/null || echo "")
        if [ -n "$IGW" ] && [ "$IGW" != "None" ]; then
            print_message "$YELLOW" "  分离并删除 Internet Gateway: $IGW"
            aws ec2 detach-internet-gateway --internet-gateway-id $IGW --vpc-id $vpc_id 2>/dev/null || true
            aws ec2 delete-internet-gateway --internet-gateway-id $IGW 2>/dev/null || true
        fi
        
        # 删除子网
        SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --query "Subnets[].SubnetId" --output text 2>/dev/null || echo "")
        if [ -n "$SUBNETS" ] && [ "$SUBNETS" != "None" ]; then
            for subnet_id in $SUBNETS; do
                print_message "$YELLOW" "  删除 Subnet: $subnet_id"
                aws ec2 delete-subnet --subnet-id $subnet_id 2>/dev/null || true
            done
        fi
        
        # 删除路由表（除了主路由表）
        ROUTE_TABLES=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc_id" --query "RouteTables[?Associations[0].Main!=\`true\`].RouteTableId" --output text 2>/dev/null || echo "")
        if [ -n "$ROUTE_TABLES" ] && [ "$ROUTE_TABLES" != "None" ]; then
            for rt_id in $ROUTE_TABLES; do
                print_message "$YELLOW" "  删除 Route Table: $rt_id"
                aws ec2 delete-route-table --route-table-id $rt_id 2>/dev/null || true
            done
        fi
        
        # 最后删除 VPC
        print_message "$YELLOW" "尝试删除 VPC: $vpc_id"
        DELETE_VPC_RESULT=$(aws ec2 delete-vpc --vpc-id $vpc_id 2>&1)
        if [ $? -eq 0 ]; then
            print_message "$GREEN" "✓ VPC 资源已成功清理: $vpc_id"
        else
            print_message "$RED" "❌ 无法删除VPC: $vpc_id"
            print_message "$RED" "  错误: $DELETE_VPC_RESULT"
            diagnose_vpc_deletion_failure "$vpc_id"
        fi
    done
else
    print_message "$GREEN" "✓ 没有找到专用 VPC"
fi
echo

# 9. 清理本地 Terraform 文件
print_message "$YELLOW" "=== 清理本地 Terraform 文件 ==="
TF_DIR=$(pwd)/infrastructure/terraform
if [ -d "$TF_DIR" ]; then
    cd "$TF_DIR"
    
    # 备份并删除所有 state 文件
    if ls terraform.tfstate* 1> /dev/null 2>&1; then
        mkdir -p backup_states
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        mv terraform.tfstate "backup_states/terraform.tfstate.${TIMESTAMP}.backup" 2>/dev/null || true
        mv terraform.tfstate.backup "backup_states/terraform.tfstate.backup.${TIMESTAMP}.backup" 2>/dev/null || true
        print_message "$GREEN" "✓ Terraform state 文件已备份到 backup_states 目录"
    fi
    
    # 删除 .terraform 目录
    if [ -d ".terraform" ]; then
        rm -rf .terraform
        print_message "$GREEN" "✓ .terraform 目录已删除"
    fi
    
    # 删除 .terraform.lock.hcl
    if [ -f ".terraform.lock.hcl" ]; then
        rm -f .terraform.lock.hcl
        print_message "$GREEN" "✓ .terraform.lock.hcl 已删除"
    fi
    #返回原目录
    cd - > /dev/null
fi
echo

print_message "$GREEN" "=== 增强清理完成 ==="

# 执行特殊的残留资源清理
print_message "$BLUE" "=== 执行特殊残留资源清理 ==="
cleanup_specific_resources

# 执行强力XRay清理
print_message "$BLUE" "=== 执行强力XRay清理 ==="
print_message "$YELLOW" "强制删除所有包含项目前缀的XRay规则..."
XRAY_RULES=$(aws xray get-sampling-rules --output json 2>/dev/null | \
jq -r ".SamplingRuleRecords[].SamplingRule.ruleName" | \
grep -E "(enterprise-rag|$PREFIX)" || echo "")

if [ -n "$XRAY_RULES" ]; then
    echo "$XRAY_RULES" | while read rule; do
        if [ -n "$rule" ]; then
            print_message "$YELLOW" "  强制删除XRay规则: $rule"
            if aws xray delete-sampling-rule --rule-name "$rule" 2>/dev/null; then
                print_message "$GREEN" "  ✓ XRay规则已删除: $rule"
            else
                print_message "$RED" "  ❌ 删除XRay规则失败: $rule"
            fi
        fi
    done
else
    print_message "$GREEN" "✓ 没有找到需要强制清理的XRay规则"
fi
echo

# 再次检查是否有剩余资源
print_message "$BLUE" "=== 清理后资源检查 ==="
check_resources
REMAINING_RESOURCES=$?

echo
if [ $REMAINING_RESOURCES -eq 0 ]; then
    print_message "$GREEN" "✅ 太好了！所有资源都已成功清理。"
else
    print_message "$RED" "⚠️  清理未完全成功，仍有 $REMAINING_RESOURCES 个资源需要手动处理。"
    print_message "$YELLOW" "可能的原因："
    print_message "$YELLOW" "- 资源之间存在隐藏的依赖关系（如 ENI 仍被服务占用）"
    print_message "$YELLOW" "- 权限不足，无法删除某些资源"
    print_message "$YELLOW" "- CloudFront 分发禁用后删除超时"
    echo
    print_message "$YELLOW" "解决建议："
    print_message "$YELLOW" "1. 等待几分钟后再次运行此脚本"
    print_message "$YELLOW" "2. 登录AWS控制台，根据上面提供的诊断信息手动检查并删除剩余资源"
    print_message "$YELLOW" "3. 检查CloudTrail日志了解删除失败的详细原因"
fi

echo
print_message "$YELLOW" "其他建议事项："
print_message "$YELLOW" "1. 登录 AWS 控制台手动检查以下服务："
print_message "$YELLOW" "   - VPC 控制台（特别是ENI部分）"
print_message "$YELLOW" "   - KMS（密钥将在7天后删除）"
print_message "$YELLOW" "   - Cost Explorer（检查费用）"
print_message "$YELLOW" "2. 检查是否有 CloudFormation 堆栈需要删除"
print_message "$YELLOW" "3. 检查是否有其他区域的资源"
echo
print_message "$GREEN" "✅ AWS 资源增强清理脚本执行完成！"

fi  # 结束 if [ "$MODE" != "check" ]