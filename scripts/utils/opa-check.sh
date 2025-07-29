#!/bin/bash
# OPA policy check utility

set -e

# 项目根目录
PROJECT_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$PROJECT_ROOT"

# 加载通用函数
source "${PROJECT_ROOT}/scripts/utils/common.sh"

# OPA 相关函数
check_opa_installed() {
    if ! command -v opa &> /dev/null; then
        print_error "OPA 未安装"
        echo "请使用以下命令安装 OPA："
        echo "  macOS: brew install opa"
        echo "  Linux: curl -L -o opa https://openpolicyagent.org/downloads/latest/opa_linux_amd64"
        return 1
    fi
    
    local version=$(opa version | grep "Version" | awk '{print $2}')
    print_success "OPA 已安装 (版本: $version)"
    return 0
}

# 运行策略测试
run_policy_tests() {
    print_info "运行策略测试..."
    
    if opa test "${PROJECT_ROOT}/policies/" -v; then
        print_success "所有策略测试通过"
        return 0
    else
        print_error "策略测试失败"
        return 1
    fi
}

# 验证策略语法
validate_policy_syntax() {
    print_info "验证策略语法..."
    
    local error_count=0
    
    # 查找所有 .rego 文件
    while IFS= read -r -d '' file; do
        if ! opa fmt --list "$file" > /dev/null 2>&1; then
            print_error "语法错误: $file"
            ((error_count++))
        fi
    done < <(find "${PROJECT_ROOT}/policies" -name "*.rego" -type f -print0)
    
    if [ $error_count -eq 0 ]; then
        print_success "所有策略语法正确"
        return 0
    else
        print_error "发现 $error_count 个语法错误"
        return 1
    fi
}

# 格式化策略文件
format_policies() {
    print_info "格式化策略文件..."
    
    local formatted_count=0
    
    while IFS= read -r -d '' file; do
        if opa fmt -w "$file" > /dev/null 2>&1; then
            ((formatted_count++))
        fi
    done < <(find "${PROJECT_ROOT}/policies" -name "*.rego" -type f -print0)
    
    print_success "格式化了 $formatted_count 个文件"
}

# 生成策略覆盖率报告
generate_coverage_report() {
    print_info "生成策略覆盖率报告..."
    
    local coverage_file="${PROJECT_ROOT}/policies/coverage.json"
    
    if opa test "${PROJECT_ROOT}/policies/" --coverage --format=json > "$coverage_file"; then
        # 解析覆盖率
        local coverage=$(jq '.coverage // 0' "$coverage_file")
        print_success "策略覆盖率: ${coverage}%"
        
        # 生成 HTML 报告
        if command -v python3 &> /dev/null; then
            python3 -m json.tool "$coverage_file" > "${PROJECT_ROOT}/policies/coverage-pretty.json"
            print_success "覆盖率报告已保存到: policies/coverage-pretty.json"
        fi
    else
        print_error "无法生成覆盖率报告"
        return 1
    fi
}

# 运行 Terraform 计划并检查策略
check_terraform_plan() {
    local env="${1:-dev}"
    print_info "检查 Terraform 计划 (环境: $env)..."
    
    # 切换到 infrastructure 目录
    cd "${PROJECT_ROOT}/infrastructure"
    
    # 生成计划
    local plan_file="/tmp/tfplan-${env}.binary"
    local json_file="/tmp/tfplan-${env}.json"
    
    print_info "生成 Terraform 计划..."
    if ! terraform plan -var-file="environments/${env}.tfvars" -out="$plan_file"; then
        print_error "Terraform 计划失败"
        return 1
    fi
    
    # 转换为 JSON
    terraform show -json "$plan_file" > "$json_file"
    
    # 运行 OPA 检查
    print_info "运行策略检查..."
    
    local violations=$(opa eval -d "${PROJECT_ROOT}/policies" -i "$json_file" \
        "data.terraform.analysis.deny[x]" --format raw 2>/dev/null || echo "[]")
    
    if [ "$violations" != "[]" ] && [ -n "$violations" ]; then
        print_error "发现策略违规:"
        echo "$violations" | jq -r '.[] | "  - " + .'
        return 1
    else
        print_success "所有策略检查通过"
        return 0
    fi
}

# 列出所有策略
list_policies() {
    print_info "已安装的策略:"
    
    echo ""
    echo "安全策略 (security/):"
    find "${PROJECT_ROOT}/policies/security" -name "*.rego" -type f 2>/dev/null | \
        xargs -I {} basename {} .rego | sed 's/^/  - /'
    
    echo ""
    echo "成本策略 (cost/):"
    find "${PROJECT_ROOT}/policies/cost" -name "*.rego" -type f 2>/dev/null | \
        xargs -I {} basename {} .rego | sed 's/^/  - /'
    
    echo ""
    echo "性能策略 (performance/):"
    find "${PROJECT_ROOT}/policies/performance" -name "*.rego" -type f 2>/dev/null | \
        xargs -I {} basename {} .rego | sed 's/^/  - /'
    
    echo ""
    echo "合规策略 (compliance/):"
    find "${PROJECT_ROOT}/policies/compliance" -name "*.rego" -type f 2>/dev/null | \
        xargs -I {} basename {} .rego | sed 's/^/  - /'
}

# 主函数
main() {
    local command="${1:-check}"
    
    case "$command" in
        check)
            check_opa_installed || exit 1
            validate_policy_syntax || exit 1
            run_policy_tests || exit 1
            ;;
        test)
            run_policy_tests || exit 1
            ;;
        format)
            format_policies
            ;;
        coverage)
            generate_coverage_report || exit 1
            ;;
        plan)
            local env="${2:-dev}"
            check_terraform_plan "$env" || exit 1
            ;;
        list)
            list_policies
            ;;
        *)
            echo "用法: $0 {check|test|format|coverage|plan|list} [环境]"
            echo ""
            echo "命令:"
            echo "  check    - 检查 OPA 安装和策略语法"
            echo "  test     - 运行策略测试"
            echo "  format   - 格式化策略文件"
            echo "  coverage - 生成覆盖率报告"
            echo "  plan     - 检查 Terraform 计划"
            echo "  list     - 列出所有策略"
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"