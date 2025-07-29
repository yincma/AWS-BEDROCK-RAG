#!/bin/bash

# 构建 OpenSearch Lambda 层脚本
set -e

echo "🔨 构建 OpenSearch Lambda 层..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
OUTPUT_DIR="$SCRIPT_DIR/output"

# 清理旧的构建
echo "清理旧的构建目录..."
rm -rf "$BUILD_DIR" "$OUTPUT_DIR"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

# 检查 Docker 是否可用
if ! command -v docker &> /dev/null; then
    echo "❌ Docker 未安装或未运行"
    echo "使用本地 Python 构建（可能会有兼容性问题）..."
    
    # 本地构建方案
    cd "$BUILD_DIR"
    mkdir -p python
    pip install -r "$SCRIPT_DIR/requirements.txt" -t python/ --platform manylinux2014_x86_64 --only-binary=:all: --no-cache-dir
    zip -r "$OUTPUT_DIR/opensearch-layer.zip" python/
else
    echo "✅ 使用 Docker 构建（推荐）..."
    
    # Docker 构建方案
    cd "$SCRIPT_DIR"
    
    # 构建 Docker 镜像
    docker build -t opensearch-lambda-layer .
    
    # 运行容器并提取 ZIP 文件
    docker run --rm -v "$OUTPUT_DIR:/output" --entrypoint sh opensearch-lambda-layer -c "cp /opt/opensearch-layer.zip /output/"
fi

# 验证构建结果
if [ -f "$OUTPUT_DIR/opensearch-layer.zip" ]; then
    echo "✅ Lambda 层构建成功！"
    echo "文件位置: $OUTPUT_DIR/opensearch-layer.zip"
    echo "文件大小: $(du -sh "$OUTPUT_DIR/opensearch-layer.zip" | cut -f1)"
    
    # 显示包含的主要模块
    echo ""
    echo "包含的主要模块："
    unzip -l "$OUTPUT_DIR/opensearch-layer.zip" | grep -E "(opensearch|boto|urllib3)" | head -10
else
    echo "❌ 构建失败"
    exit 1
fi

echo ""
echo "下一步："
echo "1. 将层上传到 AWS: aws lambda publish-layer-version --layer-name opensearch-deps --zip-file fileb://$OUTPUT_DIR/opensearch-layer.zip --compatible-runtimes python3.11"
echo "2. 更新 Lambda 函数使用新层"