#!/bin/bash

set -e

# 脚本目录和项目根目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR"
cd "$PROJECT_ROOT"

# 颜色定义（放在最前面，以便 trap 可以使用）
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 如果部署失败，提供调试建议
trap 'echo -e "\n${YELLOW}提示: 如需查看详细输出，请使用 DEBUG=true ./deploy.sh 运行${NC}"' ERR

ENVIRONMENT=${1:-dev}
REGION=${2:-us-east-1}
DEBUG=${DEBUG:-false}  # 可通过 DEBUG=true ./deploy.sh 启用调试模式

# 总步骤数
TOTAL_STEPS=6
CURRENT_STEP=0

# 进度显示函数
show_progress() {
    local step=$1
    local total=$2
    local message=$3
    local percent=$((step * 100 / total))
    
    # 清除当前行
    printf "\r\033[K"
    
    # 显示进度条
    printf "${CYAN}[%-50s] %3d%% [%d/%d] %s${NC}" \
        "$(printf '#%.0s' $(seq 1 $((percent / 2))))" \
        "$percent" \
        "$step" \
        "$total" \
        "$message"
}

# 错误处理函数
handle_error() {
    echo -e "\n${RED}❌ 错误: $1${NC}"
    echo -e "${YELLOW}详细错误信息:${NC}"
    return 1
}

# 显示警告
show_warning() {
    echo -e "\n${YELLOW}⚠️  警告: $1${NC}"
}

# 运行命令并捕获输出
run_command() {
    local cmd="$1"
    local description="$2"
    local show_output=${3:-false}  # 第三个参数控制是否显示实时输出
    local output_file=$(mktemp)
    local error_file=$(mktemp)
    
    # 调试模式下显示要执行的命令
    if [ "$DEBUG" = "true" ]; then
        echo -e "\n${CYAN}[DEBUG] 执行命令: $cmd${NC}"
    fi
    
    # 执行命令并捕获输出
    if [ "$show_output" = "true" ] || [ "$DEBUG" = "true" ]; then
        # 显示实时输出（用于 Terraform 等需要查看进度的命令）
        echo -e "\n${CYAN}执行: $description${NC}"
        if eval "$cmd"; then
            return 0
        else
            handle_error "执行 '$description' 失败"
            exit 1
        fi
    else
        # 静默执行，只在出错时显示
        if eval "$cmd" > "$output_file" 2> "$error_file"; then
            # 检查是否有警告
            if grep -i "warning\|warn\|ERROR:" "$error_file" > /dev/null 2>&1; then
                show_warning "在执行 '$description' 时发现警告:"
                grep -i "warning\|warn\|ERROR:" "$error_file" | sed 's/^/  /'
            fi
            rm -f "$output_file" "$error_file"
            return 0
        else
            # 显示错误
            handle_error "执行 '$description' 失败"
            echo -e "${RED}命令: $cmd${NC}"
            echo -e "${RED}错误输出:${NC}"
            if [ -s "$error_file" ]; then
                cat "$error_file" | sed 's/^/  /'
            else
                echo "  (无错误输出)"
            fi
            echo -e "${RED}标准输出:${NC}"
            if [ -s "$output_file" ]; then
                # 对于 Terraform，显示更多行
                if [[ "$cmd" == *"terraform"* ]]; then
                    cat "$output_file" | tail -100 | sed 's/^/  /'
                else
                    cat "$output_file" | sed 's/^/  /'
                fi
            else
                echo "  (无标准输出)"
            fi
            rm -f "$output_file" "$error_file"
            exit 1
        fi
    fi
}

# 开始部署
clear
echo "=== 完整部署AWS Bedrock RAG系统 ==="
echo "环境: $ENVIRONMENT | 区域: $REGION"
if [ "$DEBUG" = "true" ]; then
    echo "调试模式: 已启用"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 步骤0: 构建Lambda部署包
CURRENT_STEP=$((CURRENT_STEP + 1))
show_progress $CURRENT_STEP $TOTAL_STEPS "构建Lambda部署包..."
# 显示 Lambda 构建的输出，因为它有自己的进度显示
echo ""
if ! "$PROJECT_ROOT/build-lambda-packages.sh"; then
    handle_error "Lambda 包构建失败"
    exit 1
fi

# 步骤1: 初始化Terraform
CURRENT_STEP=$((CURRENT_STEP + 1))
show_progress $CURRENT_STEP $TOTAL_STEPS "初始化Terraform..."
cd "$PROJECT_ROOT/infrastructure/terraform"
# Terraform 命令显示实时输出
run_command "terraform init -upgrade" "Terraform初始化" true

# 步骤2: 部署基础设施
CURRENT_STEP=$((CURRENT_STEP + 1))
show_progress $CURRENT_STEP $TOTAL_STEPS "部署Terraform基础设施..."
# Terraform apply 需要看到实时输出
run_command "terraform apply -var=\"environment=$ENVIRONMENT\" -auto-approve" "Terraform部署" true

# 获取输出
echo -e "\n${CYAN}获取 Terraform 输出...${NC}"
API_ID=$(terraform output -raw api_gateway_id 2>/dev/null || echo "")
API_URL=$(terraform output -raw api_gateway_url 2>/dev/null || echo "")
FRONTEND_BUCKET=$(terraform output -raw frontend_bucket 2>/dev/null || echo "")
CLOUDFRONT_ID=$(terraform output -raw cloudfront_distribution_id 2>/dev/null || echo "")
CLOUDFRONT_URL=$(terraform output -raw cloudfront_url 2>/dev/null || echo "")

# 验证关键输出
if [ -z "$API_URL" ] || [ -z "$FRONTEND_BUCKET" ]; then
    handle_error "无法获取 Terraform 输出"
    echo -e "${YELLOW}请检查 Terraform 部署是否成功完成${NC}"
    echo -e "${YELLOW}尝试运行: cd infrastructure/terraform && terraform output${NC}"
    exit 1
fi

# 步骤3: 更新前端配置
CURRENT_STEP=$((CURRENT_STEP + 1))
show_progress $CURRENT_STEP $TOTAL_STEPS "更新前端配置..."
cd "$PROJECT_ROOT/applications/frontend"

# 获取认证配置
USER_POOL_ID=$(cd "$PROJECT_ROOT/infrastructure/terraform" && terraform output -json authentication 2>/dev/null | jq -r '.user_pool_id // empty' || echo "")
USER_POOL_CLIENT_ID=$(cd "$PROJECT_ROOT/infrastructure/terraform" && terraform output -json authentication 2>/dev/null | jq -r '.user_pool_client_id // empty' || echo "")

# 如果从嵌套对象获取失败，尝试直接获取单独的输出
if [ -z "$USER_POOL_ID" ]; then
    USER_POOL_ID=$(cd "$PROJECT_ROOT/infrastructure/terraform" && terraform output -raw user_pool_id 2>/dev/null || echo "")
fi
if [ -z "$USER_POOL_CLIENT_ID" ]; then
    USER_POOL_CLIENT_ID=$(cd "$PROJECT_ROOT/infrastructure/terraform" && terraform output -raw user_pool_client_id 2>/dev/null || echo "")
fi

cat > public/config.json <<EOF
{
  "apiEndpoint": "$API_URL",
  "region": "$REGION",
  "environment": "$ENVIRONMENT",
  "userPoolId": "$USER_POOL_ID",
  "userPoolClientId": "$USER_POOL_CLIENT_ID"
}
EOF

# 步骤4: 构建前端
CURRENT_STEP=$((CURRENT_STEP + 1))
show_progress $CURRENT_STEP $TOTAL_STEPS "构建前端应用..."
# npm 命令保持静默，除非出错
run_command "npm install --loglevel=error" "安装前端依赖"

# 设置环境变量供构建时使用
export REACT_APP_API_GATEWAY_URL="$API_URL"
export REACT_APP_AWS_REGION="$REGION"
export REACT_APP_USER_POOL_ID="$USER_POOL_ID"
export REACT_APP_USER_POOL_CLIENT_ID="$USER_POOL_CLIENT_ID"

run_command "npm run build" "构建前端"

# 步骤5: 部署前端到S3
CURRENT_STEP=$((CURRENT_STEP + 1))
show_progress $CURRENT_STEP $TOTAL_STEPS "部署前端到S3..."
run_command "aws s3 sync build/ s3://$FRONTEND_BUCKET --delete" "同步到S3"

# 刷新CloudFront（作为步骤5的一部分）
printf "\n${CYAN}刷新CloudFront缓存...${NC}"
if [ -n "$CLOUDFRONT_ID" ]; then
    INVALIDATION_ID=$(aws cloudfront create-invalidation \
      --distribution-id "$CLOUDFRONT_ID" \
      --paths "/*" \
      --query 'Invalidation.Id' \
      --output text 2>/dev/null || echo "")
fi

# 完成
echo -e "\n\n${GREEN}✅ 部署完成！${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "前端地址: ${CYAN}$CLOUDFRONT_URL${NC}"
echo -e "API地址: ${CYAN}$API_URL${NC}"
echo -e "${YELLOW}注意: CloudFront缓存刷新可能需要15-20分钟${NC}"

# 验证CORS
if [ -n "$API_URL" ] && [ -n "$CLOUDFRONT_URL" ]; then
    echo -e "\n正在验证CORS配置..."
    sleep 2
    CORS_CHECK=$(curl -s -X OPTIONS "$API_URL/query" \
      -H "Origin: $CLOUDFRONT_URL" \
      -H "Access-Control-Request-Method: POST" \
      -I 2>/dev/null | grep -i "access-control" || true)
    
    if [ -n "$CORS_CHECK" ]; then
        echo -e "${GREEN}✓ CORS配置正确${NC}"
    else
        show_warning "CORS验证失败，请检查API Gateway配置"
    fi
fi

echo -e "\n${GREEN}部署完成！请访问: $CLOUDFRONT_URL${NC}"