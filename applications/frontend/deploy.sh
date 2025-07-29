#!/bin/bash
set -e

# 部署前端应用到 S3
# 确保配置与 Terraform 保持一致

echo "🚀 开始部署前端应用..."

# 检查必需的环境变量
if [ -z "$S3_BUCKET" ]; then
    echo "❌ 错误：未设置 S3_BUCKET 环境变量"
    echo "请设置：export S3_BUCKET=your-bucket-name"
    exit 1
fi

# 生成配置文件
echo "📋 生成配置文件..."
npm run generate-config

# 构建应用
echo "🔨 构建应用..."
npm run build

# 上传到 S3
echo "☁️  上传到 S3..."
aws s3 sync build/ s3://$S3_BUCKET/ --delete --exclude "config.json"

# 注意：config.json 被排除，因为它由 Terraform 管理
echo "⚠️  注意：config.json 由 Terraform 管理，未上传本地版本"

# 使 CloudFront 缓存失效（如果设置了 CLOUDFRONT_DISTRIBUTION_ID）
if [ -n "$CLOUDFRONT_DISTRIBUTION_ID" ]; then
    echo "🔄 使 CloudFront 缓存失效..."
    aws cloudfront create-invalidation \
        --distribution-id $CLOUDFRONT_DISTRIBUTION_ID \
        --paths "/*"
fi

echo "✅ 部署完成！"
echo ""
echo "📝 提醒："
echo "   - config.json 由 Terraform 管理"
echo "   - 如需更新配置，请修改 Terraform 变量并运行 terraform apply"