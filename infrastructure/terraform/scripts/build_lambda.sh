#!/bin/bash
# Lambda函数构建脚本

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 函数：打印带颜色的消息
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# 函数：构建Lambda函数
build_lambda() {
    local function_name=$1
    local source_dir=$2
    local output_file=$3
    
    print_message $YELLOW "Building ${function_name}..."
    
    # 创建临时目录
    temp_dir=$(mktemp -d)
    
    # 复制源代码
    cp -r ${source_dir}/* ${temp_dir}/
    
    # 如果有requirements.txt，安装依赖
    if [ -f "${source_dir}/requirements.txt" ]; then
        print_message $YELLOW "Installing dependencies for ${function_name}..."
        pip install -r ${source_dir}/requirements.txt -t ${temp_dir}/ --upgrade
    fi
    
    # 创建ZIP文件
    cd ${temp_dir}
    zip -r ${output_file} . -x "*.pyc" -x "*__pycache__*" -x "*.dist-info/*"
    cd -
    
    # 清理临时目录
    rm -rf ${temp_dir}
    
    print_message $GREEN "✓ ${function_name} built successfully"
}

# 主脚本
main() {
    # 定义路径
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    PROJECT_ROOT="${SCRIPT_DIR}/../../.."
    LAMBDA_DIR="${PROJECT_ROOT}/applications/backend/lambda"
    DIST_DIR="${PROJECT_ROOT}/dist"
    
    # 创建dist目录
    mkdir -p ${DIST_DIR}
    
    # 构建query_handler
    if [ "$1" == "query_handler" ] || [ -z "$1" ]; then
        build_lambda "query_handler" \
            "${LAMBDA_DIR}/query_handler" \
            "${DIST_DIR}/query_handler.zip"
    fi
    
    # 构建document_processor
    if [ "$1" == "document_processor" ] || [ -z "$1" ]; then
        build_lambda "document_processor" \
            "${LAMBDA_DIR}/document_processor" \
            "${DIST_DIR}/document_processor.zip"
    fi
    
    # 构建authorizer
    if [ "$1" == "authorizer" ] || [ -z "$1" ]; then
        build_lambda "authorizer" \
            "${LAMBDA_DIR}/authorizer" \
            "${DIST_DIR}/authorizer.zip"
    fi
    
    # 构建index_creator
    if [ "$1" == "index_creator" ] || [ -z "$1" ]; then
        build_lambda "index_creator" \
            "${LAMBDA_DIR}/index_creator" \
            "${DIST_DIR}/index_creator.zip"
    fi
    
    print_message $GREEN "\n✅ All Lambda functions built successfully!"
    print_message $YELLOW "\nBuilt functions are in: ${DIST_DIR}"
}

# 运行主函数
main $@