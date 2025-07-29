#!/bin/bash

set -e

# 脚本目录和项目根目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR"
cd "$PROJECT_ROOT"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "=== 构建Lambda部署包 ==="

# 创建dist目录
mkdir -p "$PROJECT_ROOT/dist"

# Lambda函数列表
LAMBDA_FUNCTIONS=("query_handler" "document_processor" "authorizer")
TOTAL_FUNCTIONS=$((${#LAMBDA_FUNCTIONS[@]} + 1)) # +1 for index_creator
CURRENT=0

# 进度显示函数
show_build_progress() {
    local current=$1
    local total=$2
    local name=$3
    local percent=$((current * 100 / total))
    
    printf "\r${CYAN}[%-50s] %3d%% - 构建 %s${NC}" \
        "$(printf '#%.0s' $(seq 1 $((percent / 2))))" \
        "$percent" \
        "$name"
}

# 错误输出函数
show_error() {
    echo -e "\n${RED}❌ 错误: $1${NC}"
}

# 构建每个Lambda函数
for func in "${LAMBDA_FUNCTIONS[@]}"; do
    CURRENT=$((CURRENT + 1))
    show_build_progress $CURRENT $TOTAL_FUNCTIONS "$func"
    
    # 创建临时目录
    temp_dir="temp_$func"
    rm -rf "$temp_dir" # 清理旧目录，确保构建环境干净
    mkdir -p "$temp_dir"
    
    source_dir="$PROJECT_ROOT/applications/backend/lambda/$func"

    # 检查源目录是否存在
    if [ ! -d "$source_dir" ]; then
        show_error "源目录不存在: $source_dir"
        continue # 跳过此函数
    fi

    # 复制Lambda代码
    cp "$source_dir"/* "$temp_dir/" 2>/dev/null
    
    # 复制共享代码
    if [ -d "$PROJECT_ROOT/applications/backend/shared" ]; then
        cp -r "$PROJECT_ROOT/applications/backend/shared" "$temp_dir/"
    fi
    
    # 安装依赖（如果临时目录中有requirements.txt）
    if [ -f "$temp_dir/requirements.txt" ]; then
        pip_output=$(pip install -r "$temp_dir/requirements.txt" -t "$temp_dir/" --quiet 2>&1)
        if [[ "$pip_output" == *"ERROR:"* ]] || [[ "$pip_output" == *"error:"* ]]; then
            echo -e "\n${YELLOW}⚠️  pip 安装警告:${NC}"
            echo "$pip_output" | grep -i "error\|warning" | sed 's/^/  /'
        fi
    fi
    
    # 创建ZIP包
    cd "$temp_dir"
    zip -r "$PROJECT_ROOT/dist/$func.zip" . -q
    cd "$PROJECT_ROOT"
    
    # 清理临时目录
    rm -rf "$temp_dir"
    
    echo -ne "\r\033[K"
    echo "✓ $func.zip 创建完成"
done

# 构建index_creator（特殊处理）
CURRENT=$((CURRENT + 1))
show_build_progress $CURRENT $TOTAL_FUNCTIONS "index_creator"

temp_dir="temp_index_creator"
mkdir -p $temp_dir 2>/dev/null

# 复制index_creator代码
if [ -f "$PROJECT_ROOT/infrastructure/terraform/modules/bedrock/index_creator.py" ]; then
    cp "$PROJECT_ROOT/infrastructure/terraform/modules/bedrock/index_creator.py" "$temp_dir/handler.py" 2>/dev/null
else
    show_error "找不到 index_creator.py"
    exit 1
fi

# 安装依赖
if [ -f "$PROJECT_ROOT/infrastructure/terraform/modules/bedrock/lambda_requirements.txt" ]; then
    pip_output=$(pip install -r "$PROJECT_ROOT/infrastructure/terraform/modules/bedrock/lambda_requirements.txt" -t "$temp_dir/" --quiet 2>&1)
    if [[ "$pip_output" == *"ERROR:"* ]] || [[ "$pip_output" == *"error:"* ]]; then
        echo -e "\n${YELLOW}⚠️  pip 安装警告:${NC}"
        echo "$pip_output" | grep -i "error\|warning" | sed 's/^/  /'
    fi
fi

# 创建ZIP包
cd "$temp_dir"
zip -r "$PROJECT_ROOT/dist/index_creator.zip" . -q
cd "$PROJECT_ROOT"

# 清理临时目录
rm -rf "$temp_dir"

echo -ne "\r\033[K"
echo "✓ index_creator.zip 创建完成"

echo ""
echo "=== Lambda部署包构建完成 ==="
ls -lh "$PROJECT_ROOT/dist/"*.zip | awk '{print "  " $9 ": " $5}'