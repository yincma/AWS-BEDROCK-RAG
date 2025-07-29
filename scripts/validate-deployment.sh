#!/bin/bash

# 部署验证脚本
# 用于验证RAG系统部署状态并诊断常见问题

set -e

echo "=== AWS Bedrock RAG 部署验证脚本 ==="
echo "开始时间: $(date)"
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 设置默认值
REGION=${AWS_REGION:-us-east-1}
ENVIRONMENT=${ENVIRONMENT:-dev}
PROJECT_NAME=${PROJECT_NAME:-enterprise-rag}

echo "配置信息:"
echo "- AWS区域: $REGION"
echo "- 环境: $ENVIRONMENT"
echo "- 项目名称: $PROJECT_NAME"
echo ""

# 检查AWS CLI是否安装
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}错误: AWS CLI未安装${NC}"
        echo "请访问 https://aws.amazon.com/cli/ 安装AWS CLI"
        exit 1
    fi
    echo -e "${GREEN}✓${NC} AWS CLI已安装"
}

# 检查AWS凭证
check_aws_credentials() {
    if ! aws sts get-caller-identity &> /dev/null; then
        echo -e "${RED}错误: AWS凭证未配置${NC}"
        echo "请运行 'aws configure' 配置您的AWS凭证"
        exit 1
    fi
    
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    echo -e "${GREEN}✓${NC} AWS凭证有效 (账户ID: $ACCOUNT_ID)"
}

# 检查Terraform输出
check_terraform_outputs() {
    echo ""
    echo "检查Terraform输出..."
    
    if [ -d "infrastructure/terraform" ]; then
        cd infrastructure/terraform
        
        if [ -f "terraform.tfstate" ]; then
            # 获取关键输出
            KB_ID=$(terraform output -raw knowledge_base_id 2>/dev/null || echo "")
            DS_ID=$(terraform output -raw data_source_id 2>/dev/null || echo "")
            API_URL=$(terraform output -raw api_gateway_url 2>/dev/null || echo "")
            
            if [ -z "$KB_ID" ] || [ "$KB_ID" == "" ]; then
                echo -e "${RED}✗${NC} Knowledge Base ID未找到"
                echo "  请确保Terraform部署已完成并且enable_bedrock_knowledge_base=true"
            else
                echo -e "${GREEN}✓${NC} Knowledge Base ID: $KB_ID"
            fi
            
            if [ -z "$DS_ID" ] || [ "$DS_ID" == "" ]; then
                echo -e "${RED}✗${NC} Data Source ID未找到"
            else
                echo -e "${GREEN}✓${NC} Data Source ID: $DS_ID"
            fi
            
            if [ -z "$API_URL" ]; then
                echo -e "${RED}✗${NC} API Gateway URL未找到"
            else
                echo -e "${GREEN}✓${NC} API Gateway URL: $API_URL"
            fi
        else
            echo -e "${YELLOW}警告: terraform.tfstate未找到${NC}"
            echo "  请先运行 'terraform apply' 部署资源"
        fi
        
        cd - > /dev/null
    else
        echo -e "${RED}错误: infrastructure/terraform目录未找到${NC}"
    fi
}

# 检查Knowledge Base状态
check_knowledge_base() {
    echo ""
    echo "检查Knowledge Base状态..."
    
    # 列出所有Knowledge Bases
    KB_LIST=$(aws bedrock-agent list-knowledge-bases --region $REGION 2>/dev/null || echo "")
    
    if [ -z "$KB_LIST" ]; then
        echo -e "${RED}✗${NC} 无法获取Knowledge Base列表"
        return
    fi
    
    # 查找项目相关的Knowledge Base
    KB_INFO=$(echo "$KB_LIST" | jq -r ".knowledgeBaseSummaries[] | select(.name | contains(\"$PROJECT_NAME\"))")
    
    if [ -z "$KB_INFO" ]; then
        echo -e "${RED}✗${NC} 未找到项目相关的Knowledge Base"
        echo "  请确保Knowledge Base已创建"
    else
        KB_ID=$(echo "$KB_INFO" | jq -r '.knowledgeBaseId' | head -n1)
        KB_STATUS=$(echo "$KB_INFO" | jq -r '.status' | head -n1)
        
        if [ "$KB_STATUS" == "ACTIVE" ]; then
            echo -e "${GREEN}✓${NC} Knowledge Base状态: ACTIVE"
            
            # 检查Data Sources
            DS_LIST=$(aws bedrock-agent list-data-sources --knowledge-base-id $KB_ID --region $REGION 2>/dev/null || echo "")
            if [ ! -z "$DS_LIST" ]; then
                DS_COUNT=$(echo "$DS_LIST" | jq '.dataSourceSummaries | length')
                echo -e "${GREEN}✓${NC} Data Sources数量: $DS_COUNT"
            fi
        else
            echo -e "${YELLOW}⚠${NC} Knowledge Base状态: $KB_STATUS"
        fi
    fi
}

# 检查Lambda函数
check_lambda_functions() {
    echo ""
    echo "检查Lambda函数..."
    
    LAMBDA_FUNCTIONS=("query-handler" "document-processor" "authorizer")
    
    for func in "${LAMBDA_FUNCTIONS[@]}"; do
        FUNC_NAME="${PROJECT_NAME}-${func}-${ENVIRONMENT}"
        
        # 检查函数是否存在
        if aws lambda get-function --function-name $FUNC_NAME --region $REGION &> /dev/null; then
            echo -e "${GREEN}✓${NC} Lambda函数 $FUNC_NAME 存在"
            
            # 检查环境变量
            ENV_VARS=$(aws lambda get-function-configuration --function-name $FUNC_NAME --region $REGION --query 'Environment.Variables' 2>/dev/null || echo "{}")
            
            if [ "$func" == "query-handler" ]; then
                KB_ID_VAR=$(echo "$ENV_VARS" | jq -r '.KNOWLEDGE_BASE_ID // empty')
                DS_ID_VAR=$(echo "$ENV_VARS" | jq -r '.DATA_SOURCE_ID // empty')
                
                if [ -z "$KB_ID_VAR" ] || [ "$KB_ID_VAR" == "null" ]; then
                    echo -e "  ${RED}✗${NC} KNOWLEDGE_BASE_ID环境变量未设置"
                else
                    echo -e "  ${GREEN}✓${NC} KNOWLEDGE_BASE_ID: $KB_ID_VAR"
                fi
                
                if [ -z "$DS_ID_VAR" ] || [ "$DS_ID_VAR" == "null" ]; then
                    echo -e "  ${YELLOW}⚠${NC} DATA_SOURCE_ID环境变量未设置"
                else
                    echo -e "  ${GREEN}✓${NC} DATA_SOURCE_ID: $DS_ID_VAR"
                fi
            fi
        else
            echo -e "${RED}✗${NC} Lambda函数 $FUNC_NAME 不存在"
        fi
    done
}

# 检查API Gateway
check_api_gateway() {
    echo ""
    echo "检查API Gateway..."
    
    API_NAME="${PROJECT_NAME}-api-${ENVIRONMENT}"
    
    # 获取API ID
    API_ID=$(aws apigateway get-rest-apis --region $REGION --query "items[?name=='$API_NAME'].id" --output text 2>/dev/null || echo "")
    
    if [ -z "$API_ID" ]; then
        echo -e "${RED}✗${NC} API Gateway未找到"
    else
        echo -e "${GREEN}✓${NC} API Gateway ID: $API_ID"
        
        # 检查部署状态
        STAGE_NAME=$ENVIRONMENT
        if aws apigateway get-stage --rest-api-id $API_ID --stage-name $STAGE_NAME --region $REGION &> /dev/null; then
            echo -e "${GREEN}✓${NC} API Stage '$STAGE_NAME' 已部署"
            
            # 构建API URL
            API_URL="https://${API_ID}.execute-api.${REGION}.amazonaws.com/${STAGE_NAME}"
            echo -e "${GREEN}✓${NC} API URL: $API_URL"
        else
            echo -e "${RED}✗${NC} API Stage '$STAGE_NAME' 未部署"
        fi
    fi
}

# 测试API健康检查
test_api_health() {
    echo ""
    echo "测试API健康检查..."
    
    if [ ! -z "$API_URL" ]; then
        HEALTH_URL="${API_URL}/query"
        echo "测试端点: $HEALTH_URL"
        
        # 发送健康检查请求
        RESPONSE=$(curl -s -X GET "$HEALTH_URL" -H "Accept: application/json" 2>/dev/null || echo "")
        
        if [ ! -z "$RESPONSE" ]; then
            # 检查响应是否包含成功标志
            if echo "$RESPONSE" | grep -q "healthy"; then
                echo -e "${GREEN}✓${NC} API健康检查通过"
            else
                echo -e "${YELLOW}⚠${NC} API响应异常"
                echo "  响应: $RESPONSE"
            fi
        else
            echo -e "${RED}✗${NC} API无响应"
        fi
    else
        echo -e "${YELLOW}跳过: API URL未设置${NC}"
    fi
}

# 生成修复建议
generate_recommendations() {
    echo ""
    echo "=== 修复建议 ==="
    
    if [ -z "$KB_ID" ] || [ "$KB_ID" == "" ]; then
        echo ""
        echo "1. Knowledge Base未配置:"
        echo "   - 确保在terraform.tfvars中设置 enable_bedrock_knowledge_base = true"
        echo "   - 运行 'terraform apply' 创建Knowledge Base资源"
        echo "   - 运行脚本 scripts/get-knowledge-base-info.sh 获取ID"
    fi
    
    if [ ! -z "$KB_ID_VAR" ] && [ "$KB_ID_VAR" == "null" ]; then
        echo ""
        echo "2. Lambda环境变量未设置:"
        echo "   - 重新部署Lambda函数: terraform apply -target=module.query_handler"
        echo "   - 或手动更新环境变量: aws lambda update-function-configuration"
    fi
    
    echo ""
    echo "3. 完整重新部署:"
    echo "   cd infrastructure/terraform"
    echo "   terraform apply"
    echo ""
    echo "4. 验证部署:"
    echo "   terraform output"
    echo "   ./scripts/get-knowledge-base-info.sh"
}

# 主执行流程
main() {
    check_aws_cli
    check_aws_credentials
    check_terraform_outputs
    check_knowledge_base
    check_lambda_functions
    check_api_gateway
    test_api_health
    generate_recommendations
    
    echo ""
    echo "=== 验证完成 ==="
    echo "结束时间: $(date)"
}

# 执行主函数
main