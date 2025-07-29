#!/bin/bash

# 部署前资源检查脚本
# 检测可能导致冲突的已存在资源

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 参数
ENVIRONMENT=${1:-dev}
PROJECT_NAME=${2:-enterprise-rag}
AUTO_FIX=${3:-false}

# 跟踪发现的问题
ISSUES_FOUND=0

echo -e "${BLUE}=== 执行部署前资源检查 ===${NC}"
echo -e "环境: ${CYAN}${ENVIRONMENT}${NC}"
echo -e "项目: ${CYAN}${PROJECT_NAME}${NC}"
echo ""

# 检查 XRay 采样规则
check_xray_sampling_rule() {
    local rule_name="${PROJECT_NAME}-sampling-${ENVIRONMENT}"
    echo -e "${BLUE}检查 XRay 采样规则...${NC}"
    
    if aws xray get-sampling-rules --query "SamplingRuleRecords[?RuleName=='${rule_name}'].RuleName" --output text 2>/dev/null | grep -q "$rule_name"; then
        echo -e "${YELLOW}⚠️  发现已存在的 XRay 采样规则: ${rule_name}${NC}"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
        
        if [ "$AUTO_FIX" == "true" ]; then
            echo -e "${CYAN}自动修复: 尝试导入到 Terraform 状态...${NC}"
            cd "$SCRIPT_DIR/../infrastructure/terraform"
            if terraform import module.monitoring.aws_xray_sampling_rule.main[0] "$rule_name" 2>/dev/null; then
                echo -e "${GREEN}✓ 成功导入 XRay 采样规则${NC}"
                ISSUES_FOUND=$((ISSUES_FOUND - 1))
            else
                echo -e "${RED}✗ 导入失败，请手动处理${NC}"
            fi
            cd - > /dev/null
        else
            echo -e "  建议: terraform import module.monitoring.aws_xray_sampling_rule.main[0] ${rule_name}"
        fi
    else
        echo -e "${GREEN}✓ XRay 采样规则检查通过${NC}"
    fi
}

# 检查 S3 存储桶
check_s3_buckets() {
    echo -e "\n${BLUE}检查 S3 存储桶...${NC}"
    
    local buckets=(
        "${PROJECT_NAME}-documents-${ENVIRONMENT}"
        "${PROJECT_NAME}-frontend-${ENVIRONMENT}"
        "${PROJECT_NAME}-logs-${ENVIRONMENT}"
    )
    
    for bucket in "${buckets[@]}"; do
        if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
            echo -e "${YELLOW}⚠️  发现已存在的 S3 存储桶: ${bucket}${NC}"
            
            # 检查 Terraform 状态中是否有这个桶
            cd "$SCRIPT_DIR/../infrastructure/terraform" 2>/dev/null || true
            if terraform state list 2>/dev/null | grep -q "aws_s3_bucket.*${bucket}"; then
                echo -e "${GREEN}  ✓ 存储桶已在 Terraform 状态中${NC}"
            else
                echo -e "${YELLOW}  ! 存储桶不在 Terraform 状态中${NC}"
                ISSUES_FOUND=$((ISSUES_FOUND + 1))
                
                if [ "$AUTO_FIX" == "true" ]; then
                    echo -e "${CYAN}  自动修复: 尝试导入到 Terraform 状态...${NC}"
                    # 需要找到正确的资源地址
                    local resource_addr=""
                    case "$bucket" in
                        *-documents-*) resource_addr="module.storage.aws_s3_bucket.documents" ;;
                        *-frontend-*) resource_addr="module.frontend.aws_s3_bucket.frontend" ;;
                        *-logs-*) resource_addr="module.storage.aws_s3_bucket.logs" ;;
                    esac
                    
                    if [ -n "$resource_addr" ] && terraform import "$resource_addr" "$bucket" 2>/dev/null; then
                        echo -e "${GREEN}  ✓ 成功导入 S3 存储桶${NC}"
                        ISSUES_FOUND=$((ISSUES_FOUND - 1))
                    else
                        echo -e "${RED}  ✗ 导入失败，请手动处理${NC}"
                    fi
                fi
            fi
            cd - > /dev/null 2>/dev/null || true
        else
            echo -e "${GREEN}✓ S3 存储桶 ${bucket} 检查通过${NC}"
        fi
    done
}

# 检查 Lambda 函数
check_lambda_functions() {
    echo -e "\n${BLUE}检查 Lambda 函数...${NC}"
    
    local functions=(
        "${PROJECT_NAME}-query-handler-${ENVIRONMENT}"
        "${PROJECT_NAME}-document-processor-${ENVIRONMENT}"
        "${PROJECT_NAME}-authorizer-${ENVIRONMENT}"
        "${PROJECT_NAME}-index-creator-${ENVIRONMENT}"
    )
    
    for func in "${functions[@]}"; do
        if aws lambda get-function --function-name "$func" 2>/dev/null > /dev/null; then
            echo -e "${GREEN}✓ Lambda 函数已存在: ${func}${NC}"
            # Lambda 函数存在通常是正常的，Terraform 会更新它们
        else
            echo -e "  Lambda 函数不存在: ${func} (将被创建)"
        fi
    done
}

# 检查 Terraform 状态
check_terraform_state() {
    echo -e "\n${BLUE}检查 Terraform 状态...${NC}"
    
    cd "$SCRIPT_DIR/../infrastructure/terraform" 2>/dev/null || {
        echo -e "${RED}✗ 无法进入 Terraform 目录${NC}"
        return 1
    }
    
    if [ -f "terraform.tfstate" ] || [ -d ".terraform" ]; then
        echo -e "${GREEN}✓ 找到 Terraform 状态文件${NC}"
        
        # 检查状态是否锁定
        if terraform state list 2>&1 | grep -q "Error loading the state"; then
            echo -e "${YELLOW}⚠️  Terraform 状态可能被锁定或损坏${NC}"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        fi
    else
        echo -e "${YELLOW}⚠️  未找到 Terraform 状态文件，这是首次部署吗？${NC}"
    fi
    
    cd - > /dev/null
}

# 脚本目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# 执行所有检查
check_xray_sampling_rule
check_s3_buckets
check_lambda_functions
check_terraform_state

# 总结
echo -e "\n${BLUE}=== 检查完成 ===${NC}"
if [ $ISSUES_FOUND -eq 0 ]; then
    echo -e "${GREEN}✓ 未发现任何问题，可以安全部署${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠️  发现 ${ISSUES_FOUND} 个潜在问题${NC}"
    echo -e "\n建议操作:"
    echo -e "1. 使用 --auto 参数自动修复: $0 $ENVIRONMENT $PROJECT_NAME true"
    echo -e "2. 手动执行上述建议的 terraform import 命令"
    echo -e "3. 或者删除冲突的 AWS 资源后重新部署"
    exit 1
fi