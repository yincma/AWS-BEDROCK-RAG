"""
消息配置文件
集中管理所有用户界面文本，避免硬编码
"""

# 系统消息
MESSAGES = {
    # 错误消息
    "knowledge_base_not_configured": "Knowledge Base未配置。请确保已正确部署AWS资源并配置环境变量。",
    "knowledge_base_empty": "知识库中还没有任何文档。请先上传相关文档，然后再进行查询。",
    "upload_instructions": """您可以通过以下方式上传文档：
1. 使用页面左侧的「文档管理」功能
2. 将PDF、TXT或其他支持的文档拖拽上传
3. 等待文档处理完成后再进行查询""",
    "cannot_find_info": "抱歉，我无法找到相关信息来回答您的问题。",
    "service_unavailable": "服务暂时不可用，请稍后再试。",
    "bedrock_error": "AI模型服务异常，请稍后再试。",
    "auth_error": "认证失败：{error}",
    
    # 状态消息
    "ready_no_documents": "⚠️ 知识库为空！请先上传文档。点击左侧「文档管理」开始上传。",
    "ready_with_documents": "✅ 系统已就绪！已索引 {count} 个文档，可以开始查询。",
    "processing_documents": "⏳ 文档正在处理中，请稍候...",
    "indexing_failed": "❌ 最近的索引任务失败，部分文档可能无法查询。",
    "health_check_ok": "Service is healthy",
    "system_not_ready": "系统未就绪",
    
    # 调试消息
    "query_knowledge_base_log": "查询Knowledge Base: {kb_id}, 问题: {question}",
    "kb_not_found_log": "Knowledge Base中没有找到相关文档。KB_ID: {kb_id}",
    "query_complete_log": "Knowledge Base查询完成，耗时: {time:.2f}秒，来源数量: {sources}",
    "error_log": "Knowledge Base查询失败 - 类型: {error_type}, 消息: {error_msg}",
    
    # 文档相关
    "unknown_document": "未知文档",
    
    # 健康检查
    "health_check_details": {
        "status": "ok",
        "region": "{region}",
        "service": "query-handler",
        "timestamp": "{timestamp}",
        "version": "{version}",
        "memory_available": "{memory} MB",
        "environment": "{environment}"
    }
}

def get_message(key: str, **kwargs) -> str:
    """
    获取消息文本
    
    Args:
        key: 消息键
        **kwargs: 格式化参数
        
    Returns:
        格式化后的消息文本
    """
    message = MESSAGES.get(key, key)
    if isinstance(message, str) and kwargs:
        return message.format(**kwargs)
    return message

def get_knowledge_base_empty_response() -> str:
    """获取知识库为空时的完整响应消息"""
    return f"{MESSAGES['knowledge_base_empty']}\n\n{MESSAGES['upload_instructions']}"