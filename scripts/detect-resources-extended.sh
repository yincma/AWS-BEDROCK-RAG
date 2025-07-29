#!/bin/bash

# 扩展的资源检测脚本 - 支持动态资源类型配置
# 版本：1.0

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
RESOURCE_TYPES_FILE="${RESOURCE_TYPES_FILE:-$SCRIPT_DIR/resource-types.conf}"

# 源脚本
source "$SCRIPT_DIR/detect-and-import-resources.sh"

# 动态加载资源类型
load_resource_types() {
    if [ ! -f "$RESOURCE_TYPES_FILE" ]; then
        log "WARN" "资源类型配置文件不存在: $RESOURCE_TYPES_FILE"
        return 1
    fi
    
    log "INFO" "加载资源类型配置..."
    
    local line_num=0
    while IFS='|' read -r resource_type aws_type terraform_type detection_cmd import_pattern || [ -n "$resource_type" ]; do
        ((line_num++))
        
        # 跳过注释和空行
        [[ "$resource_type" =~ ^#.*$ ]] && continue
        [[ -z "$resource_type" ]] && continue
        
        # 注册资源类型
        RESOURCE_TYPES["$resource_type"]="$terraform_type"
        
        # 创建检测函数
        eval "detect_${resource_type}() {
            log \"INFO\" \"检测 $aws_type 资源...\"
            
            # 替换变量
            local cmd=\"$detection_cmd\"
            cmd=\${cmd//\\\${PROJECT_NAME}/\$PROJECT_NAME}
            cmd=\${cmd//\\\${ENVIRONMENT}/\$ENVIRONMENT}
            
            # 执行检测命令
            local resources=\$(\$cmd 2>/dev/null | jq -r '.[]' || true)
            
            local orphaned=()
            for resource in \$resources; do
                if ! terraform state list 2>/dev/null | grep -q \"$terraform_type.*\$resource\"; then
                    orphaned+=(\"\$resource\")
                    log \"WARN\" \"发现孤立的 $aws_type: \$resource\"
                fi
            done
            
            echo \"\${orphaned[@]}\"
        }"
        
        # 创建导入地址查找函数
        eval "find_${resource_type}_address() {
            local resource_name=\$1
            local pattern=\"$import_pattern\"
            
            # 替换变量
            pattern=\${pattern//\\\${PROJECT_NAME}/\$PROJECT_NAME}
            pattern=\${pattern//\\\${ENVIRONMENT}/\$ENVIRONMENT}
            pattern=\${pattern//\\\${RESOURCE_NAME}/\$resource_name}
            
            # 特殊处理
            case \"$resource_type\" in
                s3_bucket)
                    if [[ \"\$resource_name\" == *\"raw-data\"* ]]; then
                        pattern=\${pattern//\\\${BUCKET_TYPE}/raw_data}
                    elif [[ \"\$resource_name\" == *\"processed-data\"* ]]; then
                        pattern=\${pattern//\\\${BUCKET_TYPE}/processed_data}
                    fi
                    ;;
                lambda_function)
                    local module_name=\"lambda\"
                    if [[ \"\$resource_name\" == *\"query-handler\"* ]]; then
                        module_name=\"query_handler\"
                    elif [[ \"\$resource_name\" == *\"document-processor\"* ]]; then
                        module_name=\"document_processor\"
                    fi
                    pattern=\${pattern//\\\${MODULE_NAME}/\$module_name}
                    ;;
            esac
            
            echo \"\$pattern\"
        }"
        
        log "DEBUG" "已加载资源类型: $resource_type"
    done < "$RESOURCE_TYPES_FILE"
    
    log "INFO" "资源类型配置加载完成"
}

# 扩展的主函数
main_extended() {
    init_log
    print_title "🔍 AWS资源孤立检测和导入工具 (扩展版)"
    
    log "INFO" "开始资源检测..."
    check_dependencies
    
    # 加载资源类型
    load_resource_types
    
    # 确保在Terraform目录中
    if [ ! -d "$TERRAFORM_DIR" ]; then
        log "ERROR" "Terraform目录不存在: $TERRAFORM_DIR"
        exit 1
    fi
    
    cd "$TERRAFORM_DIR"
    
    # 初始化Terraform（如果需要）
    if [ ! -d ".terraform" ]; then
        log "INFO" "初始化Terraform..."
        terraform init
    fi
    
    # 刷新状态
    log "INFO" "刷新Terraform状态..."
    terraform refresh > /dev/null 2>&1 || log "WARN" "状态刷新失败，继续..."
    
    # 检测各类资源
    local total_orphaned=0
    local imported_count=0
    
    # 动态检测所有配置的资源类型
    for resource_type in "${!RESOURCE_TYPES[@]}"; do
        # 检查是否有对应的检测函数
        if type -t "detect_${resource_type}" &>/dev/null; then
            echo
            print_title "检测 ${resource_type//_/ }"
            
            # 调用检测函数
            local resources=($(detect_${resource_type}))
            
            for resource in "${resources[@]}"; do
                if [ -n "$resource" ]; then
                    ((total_orphaned++))
                    
                    # 获取建议的Terraform地址
                    local suggested_addr=""
                    if type -t "find_${resource_type}_address" &>/dev/null; then
                        suggested_addr=$(find_${resource_type}_address "$resource")
                    else
                        suggested_addr=$(find_terraform_address "$resource_type" "$resource")
                    fi
                    
                    interactive_import "$resource_type" "$resource" "$suggested_addr"
                    [ $? -eq 0 ] && ((imported_count++))
                fi
            done
        else
            log "DEBUG" "跳过资源类型 $resource_type (无检测函数)"
        fi
    done
    
    # 总结
    echo
    print_title "📊 检测总结"
    echo -e "总计发现孤立资源: ${YELLOW}$total_orphaned${NC}"
    echo -e "成功导入资源数: ${GREEN}$imported_count${NC}"
    echo -e "日志文件: ${CYAN}$LOG_FILE${NC}"
    
    if [ "$total_orphaned" -gt 0 ] && [ "$imported_count" -eq "$total_orphaned" ]; then
        log "INFO" "所有孤立资源已成功导入！"
        return 0
    elif [ "$total_orphaned" -eq 0 ]; then
        log "INFO" "未发现孤立资源，环境干净！"
        return 0
    else
        log "WARN" "部分资源未导入，请查看日志了解详情"
        return 1
    fi
}

# 如果直接运行，使用扩展的主函数
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    # 保存原始main函数
    original_main=$(declare -f main)
    
    # 使用扩展的主函数
    main() {
        main_extended
    }
    
    # 处理参数（继承自原脚本）
    main "$@"
fi