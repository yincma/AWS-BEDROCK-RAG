#!/bin/bash

set -e

# Script directory and project root directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR"
cd "$PROJECT_ROOT"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "=== Building Lambda deployment packages ==="

# Create dist directory
mkdir -p "$PROJECT_ROOT/dist"

# Lambda function list
LAMBDA_FUNCTIONS=("query_handler" "document_processor" "authorizer")
TOTAL_FUNCTIONS=$((${#LAMBDA_FUNCTIONS[@]} + 1)) # +1 for index_creator
CURRENT=0

# Progress display function
show_build_progress() {
    local current=$1
    local total=$2
    local name=$3
    local percent=$((current * 100 / total))
    
    printf "\r${CYAN}[%-50s] %3d%% - Building %s${NC}" \
        "$(printf '#%.0s' $(seq 1 $((percent / 2))))" \
        "$percent" \
        "$name"
}

# Error output function
show_error() {
    echo -e "\n${RED}❌ Error: $1${NC}"
}

# Build each Lambda function
for func in "${LAMBDA_FUNCTIONS[@]}"; do
    CURRENT=$((CURRENT + 1))
    show_build_progress $CURRENT $TOTAL_FUNCTIONS "$func"
    
    # Create temporary directory
    temp_dir="temp_$func"
    rm -rf "$temp_dir" # Clean up old directory to ensure clean build environment
    mkdir -p "$temp_dir"
    
    source_dir="$PROJECT_ROOT/applications/backend/lambda/$func"

    # Check if source directory exists
    if [ ! -d "$source_dir" ]; then
        show_error "Source directory does not exist: $source_dir"
        continue # Skip this function
    fi

    # Copy Lambda code
    cp "$source_dir"/* "$temp_dir/" 2>/dev/null
    
    # Copy shared code
    if [ -d "$PROJECT_ROOT/applications/backend/shared" ]; then
        cp -r "$PROJECT_ROOT/applications/backend/shared" "$temp_dir/"
    fi
    
    # Install dependencies (if requirements.txt exists in temp directory)
    if [ -f "$temp_dir/requirements.txt" ]; then
        pip_output=$(pip install -r "$temp_dir/requirements.txt" -t "$temp_dir/" --quiet 2>&1)
        if [[ "$pip_output" == *"ERROR:"* ]] || [[ "$pip_output" == *"error:"* ]]; then
            echo -e "\n${YELLOW}⚠️  pip installation warning:${NC}"
            echo "$pip_output" | grep -i "error\|warning" | sed 's/^/  /'
        fi
    fi
    
    # Create ZIP package
    cd "$temp_dir"
    zip -r "$PROJECT_ROOT/dist/$func.zip" . -q
    cd "$PROJECT_ROOT"
    
    # Clean up temporary directory
    rm -rf "$temp_dir"
    
    echo -ne "\r\033[K"
    echo "✓ $func.zip created successfully"
done

# Build index_creator (special handling)
CURRENT=$((CURRENT + 1))
show_build_progress $CURRENT $TOTAL_FUNCTIONS "index_creator"

temp_dir="temp_index_creator"
mkdir -p $temp_dir 2>/dev/null

# Copy index_creator code
if [ -f "$PROJECT_ROOT/applications/backend/lambda/index_creator/index.py" ]; then
    cp "$PROJECT_ROOT/applications/backend/lambda/index_creator/index.py" "$temp_dir/index.py" 2>/dev/null
else
    show_error "Cannot find index_creator/index.py"
    exit 1
fi

# Install dependencies
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
echo "✓ index_creator.zip created successfully"

echo ""
echo "=== Lambda deployment packages build completed ==="
ls -lh "$PROJECT_ROOT/dist/"*.zip | awk '{print "  " $9 ": " $5}'