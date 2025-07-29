#!/bin/bash

# Frontend Deployment Script with Auto-build

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 脚本目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

# 打印带颜色的消息
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

print_message "$BLUE" "=== Frontend Deployment Script ==="
echo

# 进入前端目录
cd "$PROJECT_ROOT/applications/frontend"

# 检查是否需要安装依赖
if [ ! -d "node_modules" ] || [ "package.json" -nt "node_modules" ]; then
    print_message "$YELLOW" "Installing dependencies..."
    npm install
fi

# 获取认证配置并生成 config.json
print_message "$YELLOW" "Generating frontend configuration..."
cd "$PROJECT_ROOT/infrastructure/terraform"

# 获取所有必需的配置
API_ENDPOINT=$(terraform output -raw api_gateway_url 2>/dev/null || echo "")
REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
USER_POOL_ID=$(terraform output -json authentication 2>/dev/null | jq -r '.user_pool_id // empty' || echo "")
USER_POOL_CLIENT_ID=$(terraform output -json authentication 2>/dev/null | jq -r '.user_pool_client_id // empty' || echo "")

# 如果从嵌套对象获取失败，尝试直接获取单独的输出
if [ -z "$USER_POOL_ID" ]; then
    USER_POOL_ID=$(terraform output -raw user_pool_id 2>/dev/null || echo "")
fi
if [ -z "$USER_POOL_CLIENT_ID" ]; then
    USER_POOL_CLIENT_ID=$(terraform output -raw user_pool_client_id 2>/dev/null || echo "")
fi

# 验证配置值
if [ -z "$USER_POOL_ID" ] || [ -z "$USER_POOL_CLIENT_ID" ]; then
    print_message "$YELLOW" "⚠️  Warning: Cognito configuration is missing"
    print_message "$YELLOW" "   USER_POOL_ID: $USER_POOL_ID"
    print_message "$YELLOW" "   USER_POOL_CLIENT_ID: $USER_POOL_CLIENT_ID"
fi

if [ -z "$API_ENDPOINT" ]; then
    print_message "$YELLOW" "⚠️  Warning: API endpoint is missing"
fi

# 生成配置文件
cd "$PROJECT_ROOT/applications/frontend"
cat > public/config.json <<EOF
{
  "apiEndpoint": "$API_ENDPOINT",
  "region": "$REGION",
  "environment": "production",
  "userPoolId": "$USER_POOL_ID",
  "userPoolClientId": "$USER_POOL_CLIENT_ID"
}
EOF

print_message "$GREEN" "✓ Configuration generated"
print_message "$BLUE" "  API Endpoint: ${API_ENDPOINT:-'NOT SET'}"
print_message "$BLUE" "  Region: $REGION"
print_message "$BLUE" "  User Pool ID: ${USER_POOL_ID:-'NOT SET'}"
print_message "$BLUE" "  User Pool Client ID: ${USER_POOL_CLIENT_ID:-'NOT SET'}"

# 构建前端应用（设置环境变量供构建时使用）
print_message "$YELLOW" "Building frontend application..."
export REACT_APP_API_GATEWAY_URL="$API_ENDPOINT"
export REACT_APP_AWS_REGION="$REGION"
export REACT_APP_USER_POOL_ID="$USER_POOL_ID"
export REACT_APP_USER_POOL_CLIENT_ID="$USER_POOL_CLIENT_ID"
npm run build

# 获取S3 bucket名称
print_message "$YELLOW" "Getting S3 bucket name from Terraform outputs..."
cd "$PROJECT_ROOT/infrastructure/terraform"

# 确保Terraform已初始化
if [ ! -d ".terraform" ]; then
    terraform init -upgrade > /dev/null 2>&1
fi

# 获取前端bucket名称
FRONTEND_BUCKET=$(terraform output -raw frontend_bucket_name 2>/dev/null || echo "")

if [ -z "$FRONTEND_BUCKET" ]; then
    print_message "$RED" "❌ Could not get frontend bucket name from Terraform outputs"
    exit 1
fi

print_message "$GREEN" "✓ Frontend bucket: $FRONTEND_BUCKET"

# 返回前端目录
cd "$PROJECT_ROOT/applications/frontend"

# 同步构建文件到S3
print_message "$YELLOW" "Deploying to S3..."
aws s3 sync build/ "s3://${FRONTEND_BUCKET}/" --delete \
    --exclude "*.map" \
    --cache-control "public, max-age=3600" \
    --metadata-directive REPLACE

# 为index.html设置较短的缓存时间
aws s3 cp build/index.html "s3://${FRONTEND_BUCKET}/index.html" \
    --cache-control "public, max-age=300" \
    --content-type "text/html" \
    --metadata-directive REPLACE

# 获取CloudFront distribution ID
print_message "$YELLOW" "Getting CloudFront distribution ID..."
cd "$PROJECT_ROOT/infrastructure/terraform"
DISTRIBUTION_ID=$(terraform output -raw cloudfront_distribution_id 2>/dev/null || echo "")

if [ -n "$DISTRIBUTION_ID" ] && [ "$DISTRIBUTION_ID" != "" ]; then
    print_message "$YELLOW" "Creating CloudFront invalidation..."
    aws cloudfront create-invalidation \
        --distribution-id "$DISTRIBUTION_ID" \
        --paths "/*" \
        --query "Invalidation.Id" \
        --output text
    
    print_message "$GREEN" "✓ CloudFront invalidation created"
else
    print_message "$YELLOW" "⚠️  No CloudFront distribution found, skipping invalidation"
fi

# 获取访问URL
CLOUDFRONT_URL=$(terraform output -raw frontend_url 2>/dev/null || echo "")

print_message "$GREEN" "✅ Frontend deployment completed!"
echo
if [ -n "$CLOUDFRONT_URL" ]; then
    print_message "$BLUE" "🌐 Frontend URL: $CLOUDFRONT_URL"
else
    print_message "$CYAN" "🌐 Frontend URL: https://${FRONTEND_BUCKET}.s3.amazonaws.com/index.html"
fi
echo

# 验证部署
print_message "$YELLOW" "Verifying deployment..."
if [ -n "$CLOUDFRONT_URL" ]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$CLOUDFRONT_URL" || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        print_message "$GREEN" "✓ Frontend is accessible (HTTP $HTTP_CODE)"
    else
        print_message "$YELLOW" "⚠️  Frontend returned HTTP $HTTP_CODE (may need time to propagate)"
    fi
fi