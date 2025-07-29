#!/bin/bash

# AWS RAG System Pre-deployment Check Script
# Version: 1.0
# Description: 部署前置检查脚本，验证环境和依赖

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查结果统计
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

# 脚本目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# 打印带颜色的消息
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# 打印检查结果
print_check_result() {
    local check_status=$1
    local check_name=$2
    local message=$3
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    case $check_status in
        "PASS")
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
            echo -e "${GREEN}✓${NC} $check_name: $message"
            ;;
        "FAIL")
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
            echo -e "${RED}✗${NC} $check_name: $message"
            ;;
        "WARN")
            WARNING_CHECKS=$((WARNING_CHECKS + 1))
            echo -e "${YELLOW}⚠${NC} $check_name: $message"
            ;;
    esac
}

# 检查命令是否存在
check_command() {
    local cmd=$1
    local required=$2
    local min_version=$3
    
    if command -v "$cmd" &> /dev/null; then
        local version=$(eval "$cmd --version 2>/dev/null | head -n1" || echo "版本未知")
        
        if [ -n "$min_version" ]; then
            # 这里可以添加版本比较逻辑
            print_check_result "PASS" "$cmd" "已安装 - $version"
        else
            print_check_result "PASS" "$cmd" "已安装 - $version"
        fi
        return 0
    else
        if [ "$required" = "required" ]; then
            print_check_result "FAIL" "$cmd" "未安装 (必需)"
            return 1
        else
            print_check_result "WARN" "$cmd" "未安装 (可选)"
            return 0
        fi
    fi
}

# 检查AWS凭证
check_aws_credentials() {
    print_message "$BLUE" "\n检查AWS凭证配置..."
    
    if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
        print_check_result "PASS" "AWS环境变量" "已设置"
    elif [ -f "$HOME/.aws/credentials" ]; then
        print_check_result "PASS" "AWS凭证文件" "存在于 ~/.aws/credentials"
    else
        print_check_result "FAIL" "AWS凭证" "未找到AWS凭证配置"
        print_message "$YELLOW" "  修复建议: 运行 'aws configure' 或设置 AWS_ACCESS_KEY_ID 和 AWS_SECRET_ACCESS_KEY 环境变量"
        return 1
    fi
    
    # 验证凭证是否有效
    if aws sts get-caller-identity &> /dev/null; then
        local account_id=$(aws sts get-caller-identity --query Account --output text)
        print_check_result "PASS" "AWS凭证验证" "有效 (账户: $account_id)"
    else
        print_check_result "FAIL" "AWS凭证验证" "无效或已过期"
        return 1
    fi
    
    # 检查默认区域
    local region="${AWS_DEFAULT_REGION:-$(aws configure get region)}"
    if [ -n "$region" ]; then
        print_check_result "PASS" "AWS默认区域" "$region"
    else
        print_check_result "WARN" "AWS默认区域" "未设置，将使用 us-east-1"
    fi
}

# 检查Terraform
check_terraform() {
    print_message "$BLUE" "\n检查Terraform..."
    
    if command -v terraform &> /dev/null; then
        local tf_version=$(terraform version -json 2>/dev/null | jq -r '.terraform_version' || terraform version | head -n1 | cut -d' ' -f2)
        print_check_result "PASS" "Terraform" "版本 $tf_version"
        
        # 检查版本是否符合要求（假设需要 >= 1.0）
        local major_version=$(echo "$tf_version" | cut -d'.' -f1 | sed 's/v//')
        if [ "$major_version" -ge 1 ]; then
            print_check_result "PASS" "Terraform版本" "符合要求 (>= 1.0)"
        else
            print_check_result "WARN" "Terraform版本" "建议升级到 1.0 或更高版本"
        fi
    else
        print_check_result "FAIL" "Terraform" "未安装"
        print_message "$YELLOW" "  修复建议: 访问 https://www.terraform.io/downloads.html 下载安装"
        return 1
    fi
}

# 检查Node.js和npm
check_nodejs() {
    print_message "$BLUE" "\n检查Node.js环境..."
    
    if command -v node &> /dev/null; then
        local node_version=$(node --version)
        print_check_result "PASS" "Node.js" "版本 $node_version"
        
        # 检查版本是否符合要求（假设需要 >= 14）
        local major_version=$(echo "$node_version" | cut -d'.' -f1 | sed 's/v//')
        if [ "$major_version" -ge 14 ]; then
            print_check_result "PASS" "Node.js版本" "符合要求 (>= 14)"
        else
            print_check_result "WARN" "Node.js版本" "建议升级到 14 或更高版本"
        fi
    else
        print_check_result "FAIL" "Node.js" "未安装"
        print_message "$YELLOW" "  修复建议: 访问 https://nodejs.org/ 下载安装"
        return 1
    fi
    
    # 检查npm
    if command -v npm &> /dev/null; then
        local npm_version=$(npm --version)
        print_check_result "PASS" "npm" "版本 $npm_version"
    else
        print_check_result "WARN" "npm" "未安装"
    fi
}

# 检查Python
check_python() {
    print_message "$BLUE" "\n检查Python环境..."
    
    if command -v python3 &> /dev/null; then
        local python_version=$(python3 --version 2>&1 | cut -d' ' -f2)
        print_check_result "PASS" "Python3" "版本 $python_version"
        
        # 检查版本是否符合要求（假设需要 >= 3.8）
        local major_version=$(echo "$python_version" | cut -d'.' -f1)
        local minor_version=$(echo "$python_version" | cut -d'.' -f2)
        if [ "$major_version" -eq 3 ] && [ "$minor_version" -ge 8 ]; then
            print_check_result "PASS" "Python版本" "符合要求 (>= 3.8)"
        else
            print_check_result "WARN" "Python版本" "建议使用 3.8 或更高版本"
        fi
    else
        print_check_result "FAIL" "Python3" "未安装"
        print_message "$YELLOW" "  修复建议: 访问 https://www.python.org/downloads/ 下载安装"
        return 1
    fi
    
    # 检查pip
    if command -v pip3 &> /dev/null; then
        local pip_version=$(pip3 --version | cut -d' ' -f2)
        print_check_result "PASS" "pip3" "版本 $pip_version"
    else
        print_check_result "WARN" "pip3" "未安装"
        print_message "$YELLOW" "  修复建议: 运行 'python3 -m ensurepip'"
    fi
}

# 检查其他工具
check_other_tools() {
    print_message "$BLUE" "\n检查其他必要工具..."
    
    check_command "aws" "required"
    check_command "jq" "required"
    check_command "git" "required"
    check_command "curl" "required"
    check_command "zip" "required"
    check_command "docker" "optional"
}

# 检查项目结构
check_project_structure() {
    print_message "$BLUE" "\n检查项目结构..."
    
    local required_dirs=(
        "infrastructure"
        "applications"
        "config"
        "scripts"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [ -d "$PROJECT_ROOT/$dir" ]; then
            print_check_result "PASS" "目录: $dir" "存在"
        else
            print_check_result "WARN" "目录: $dir" "不存在"
        fi
    done
    
    # 检查重要配置文件
    local config_files=(
        "config/app_config.yaml"
        "config/model_config.yaml"
    )
    
    for file in "${config_files[@]}"; do
        if [ -f "$PROJECT_ROOT/$file" ]; then
            print_check_result "PASS" "配置文件: $file" "存在"
        else
            print_check_result "WARN" "配置文件: $file" "不存在"
        fi
    done
}

# 检查环境配置
check_environment_config() {
    print_message "$BLUE" "\n检查环境配置..."
    
    local env="${ENVIRONMENT:-dev}"
    local env_file="$PROJECT_ROOT/environments/$env/config.yaml"
    
    if [ -f "$env_file" ]; then
        print_check_result "PASS" "环境配置: $env" "存在"
        
        # 验证YAML格式
        if command -v yq &> /dev/null; then
            if yq eval '.' "$env_file" &> /dev/null; then
                print_check_result "PASS" "配置格式" "YAML格式正确"
            else
                print_check_result "FAIL" "配置格式" "YAML格式错误"
            fi
        fi
    else
        print_check_result "WARN" "环境配置: $env" "不存在，将使用默认配置"
    fi
}

# 检查磁盘空间
check_disk_space() {
    print_message "$BLUE" "\n检查磁盘空间..."
    
    # 兼容macOS和Linux的df命令
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        local available_space=$(df -g "$PROJECT_ROOT" | awk 'NR==2 {print $4}')
    else
        # Linux
        local available_space=$(df -BG "$PROJECT_ROOT" | awk 'NR==2 {print $4}' | sed 's/G//')
    fi
    
    # 确保available_space是数字
    if [[ "$available_space" =~ ^[0-9]+$ ]]; then
        if [ "$available_space" -ge 5 ]; then
            print_check_result "PASS" "磁盘空间" "${available_space}GB 可用"
        elif [ "$available_space" -ge 2 ]; then
            print_check_result "WARN" "磁盘空间" "${available_space}GB 可用 (建议至少5GB)"
        else
            print_check_result "FAIL" "磁盘空间" "${available_space}GB 可用 (不足)"
        fi
    else
        print_check_result "WARN" "磁盘空间" "无法获取磁盘空间信息"
    fi
}

# 生成检查报告
generate_report() {
    print_message "$BLUE" "\n========== 检查报告 =========="
    
    echo -e "总检查项: $TOTAL_CHECKS"
    echo -e "${GREEN}通过: $PASSED_CHECKS${NC}"
    echo -e "${YELLOW}警告: $WARNING_CHECKS${NC}"
    echo -e "${RED}失败: $FAILED_CHECKS${NC}"
    
    if [ $FAILED_CHECKS -eq 0 ]; then
        print_message "$GREEN" "\n✅ 所有必需检查都已通过！"
        return 0
    else
        print_message "$RED" "\n❌ 存在 $FAILED_CHECKS 个失败的检查项，请修复后再继续部署。"
        return 1
    fi
}

# 并行执行检查（简化版本）
run_parallel_checks() {
    # 由于bash的限制，这里使用顺序执行
    # 在实际项目中可以使用GNU parallel或其他工具实现真正的并行
    
    local checks=(
        "check_aws_credentials"
        "check_terraform"
        "check_nodejs"
        "check_python"
        "check_other_tools"
        "check_project_structure"
        "check_environment_config"
        "check_disk_space"
    )
    
    for check in "${checks[@]}"; do
        $check || true  # 继续执行即使某个检查失败
    done
}

# 主函数
main() {
    print_message "$BLUE" "========================================"
    print_message "$BLUE" "AWS RAG System 部署前置检查"
    print_message "$BLUE" "========================================"
    
    # 执行所有检查
    run_parallel_checks
    
    # 生成报告
    generate_report
    
    exit $?
}

# 处理命令行参数
if [ $# -gt 0 ]; then
    case "$1" in
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --help, -h     显示帮助信息"
            echo "  --json         以JSON格式输出结果"
            echo "  --quiet        静默模式，只显示错误"
            echo ""
            exit 0
            ;;
        --json)
            # TODO: 实现JSON输出
            echo '{"error": "JSON output not implemented yet"}'
            exit 1
            ;;
        --quiet)
            # TODO: 实现静默模式
            exec > /dev/null
            ;;
    esac
fi

# 执行主函数
main