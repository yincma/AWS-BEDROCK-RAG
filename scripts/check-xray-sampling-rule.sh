#!/bin/bash

# 检查 XRay 采样规则是否已存在的脚本
# 用于避免重复创建资源

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 获取环境参数
ENVIRONMENT=${1:-dev}
PROJECT_NAME=${2:-enterprise-rag}
RULE_NAME="${PROJECT_NAME}-sampling-${ENVIRONMENT}"

echo -e "${BLUE}检查 XRay 采样规则: ${RULE_NAME}${NC}"

# 检查规则是否存在
if aws xray get-sampling-rules --query "SamplingRuleRecords[?RuleName=='${RULE_NAME}'].RuleName" --output text 2>/dev/null | grep -q "$RULE_NAME"; then
    echo -e "${YELLOW}⚠️  XRay 采样规则 '${RULE_NAME}' 已存在${NC}"
    
    # 获取规则详细信息
    echo -e "\n${BLUE}规则详细信息:${NC}"
    aws xray get-sampling-rules --query "SamplingRuleRecords[?RuleName=='${RULE_NAME}']" --output json | jq '.[0]'
    
    echo -e "\n${YELLOW}解决方案:${NC}"
    echo "1. 导入现有规则到 Terraform:"
    echo "   cd infrastructure/terraform"
    echo "   terraform import module.monitoring.aws_xray_sampling_rule.main[0] ${RULE_NAME}"
    echo ""
    echo "2. 或删除现有规则后重新部署:"
    echo "   aws xray delete-sampling-rule --rule-name ${RULE_NAME}"
    echo ""
    echo "3. 或在部署时跳过资源检测:"
    echo "   ./deploy.sh --env ${ENVIRONMENT} --skip-resource-check"
    
    exit 1
else
    echo -e "${GREEN}✓ XRay 采样规则 '${RULE_NAME}' 不存在，可以安全创建${NC}"
    exit 0
fi