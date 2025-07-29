#!/bin/bash

# 验证Lambda函数配置的脚本
# 用于检查环境变量和Layer配置是否正确

echo "=== Lambda 配置验证脚本 ==="
echo ""

# 加载环境变量（如果存在.env文件）
if [ -f .env ]; then
    echo "📋 加载 .env 文件..."
    export $(cat .env | grep -v '^#' | xargs)
fi

# 设置变量（使用环境变量或默认值）
PROJECT_NAME=${PROJECT_NAME:-"enterprise-rag"}
ENVIRONMENT=${ENVIRONMENT:-"dev"}
REGION=${AWS_REGION:-"us-east-1"}

# Lambda函数列表
LAMBDA_FUNCTIONS=(
    "${PROJECT_NAME}-document-processor-${ENVIRONMENT}"
    "${PROJECT_NAME}-query-handler-${ENVIRONMENT}"
    "${PROJECT_NAME}-authorizer-${ENVIRONMENT}"
)

# 检查AWS CLI是否已安装
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI 未安装。请先安装 AWS CLI。"
    exit 1
fi

echo "📋 检查 Lambda 函数配置..."
echo ""

for FUNCTION_NAME in "${LAMBDA_FUNCTIONS[@]}"; do
    echo "🔍 检查函数: $FUNCTION_NAME"
    echo "----------------------------------------"
    
    # 检查函数是否存在
    if aws lambda get-function --function-name "$FUNCTION_NAME" --region "$REGION" &> /dev/null; then
        echo "✅ 函数存在"
        
        # 获取函数配置
        CONFIG=$(aws lambda get-function-configuration --function-name "$FUNCTION_NAME" --region "$REGION" 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            # 检查环境变量
            echo ""
            echo "📦 环境变量:"
            echo "$CONFIG" | jq -r '.Environment.Variables | to_entries | .[] | "  - \(.key): \(.value)"' 2>/dev/null || echo "  无环境变量配置"
            
            # 检查Layers
            echo ""
            echo "🔗 Layers:"
            LAYERS=$(echo "$CONFIG" | jq -r '.Layers[]?.Arn' 2>/dev/null)
            if [ -z "$LAYERS" ]; then
                echo "  ❌ 没有配置任何 Layer"
            else
                echo "$LAYERS" | while read -r layer; do
                    echo "  ✅ $layer"
                done
            fi
            
            # 检查关键环境变量
            echo ""
            echo "🔑 关键环境变量检查:"
            
            # 检查S3_BUCKET
            S3_BUCKET=$(echo "$CONFIG" | jq -r '.Environment.Variables.S3_BUCKET // empty' 2>/dev/null)
            if [ -n "$S3_BUCKET" ]; then
                echo "  ✅ S3_BUCKET: $S3_BUCKET"
            else
                echo "  ❌ S3_BUCKET 未设置"
            fi
            
            # 检查KNOWLEDGE_BASE_ID
            KB_ID=$(echo "$CONFIG" | jq -r '.Environment.Variables.KNOWLEDGE_BASE_ID // empty' 2>/dev/null)
            if [ -n "$KB_ID" ]; then
                echo "  ✅ KNOWLEDGE_BASE_ID: $KB_ID"
            else
                echo "  ⚠️  KNOWLEDGE_BASE_ID 未设置"
            fi
            
            # 检查DATA_SOURCE_ID
            DS_ID=$(echo "$CONFIG" | jq -r '.Environment.Variables.DATA_SOURCE_ID // empty' 2>/dev/null)
            if [ -n "$DS_ID" ]; then
                echo "  ✅ DATA_SOURCE_ID: $DS_ID"
            else
                echo "  ⚠️  DATA_SOURCE_ID 未设置"
            fi
            
        else
            echo "❌ 无法获取函数配置"
        fi
    else
        echo "❌ 函数不存在"
    fi
    
    echo ""
    echo ""
done

# 检查S3存储桶
echo "🪣 检查 S3 存储桶..."
echo "----------------------------------------"

# 从Terraform输出获取S3存储桶名称
cd ../infrastructure/terraform 2>/dev/null
if [ -f terraform.tfstate ]; then
    S3_BUCKET_NAME=$(terraform output -raw document_bucket_name 2>/dev/null)
    if [ -n "$S3_BUCKET_NAME" ]; then
        echo "✅ S3 存储桶: $S3_BUCKET_NAME"
        
        # 检查存储桶是否存在
        if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" 2>/dev/null; then
            echo "✅ 存储桶存在并可访问"
            
            # 列出文档数量
            DOC_COUNT=$(aws s3 ls "s3://$S3_BUCKET_NAME/documents/" --recursive 2>/dev/null | wc -l)
            echo "📄 文档数量: $DOC_COUNT"
        else
            echo "❌ 存储桶不存在或无法访问"
        fi
    else
        echo "❌ 无法从 Terraform 输出获取存储桶名称"
    fi
else
    echo "⚠️  未找到 terraform.tfstate 文件"
fi

echo ""
echo "=== 验证完成 ==="
echo ""
echo "📌 后续步骤："
echo "1. 如果发现配置问题，请运行: cd infrastructure/terraform && terraform apply"
echo "2. 检查 CloudWatch 日志: aws logs tail /aws/lambda/${PROJECT_NAME}-document-processor-${ENVIRONMENT} --follow"
echo "3. 测试 API: curl https://your-api-gateway-url/dev/documents"