"""
Message configuration file
Centrally manage all user interface text, avoiding hard coding
"""

# System messages
MESSAGES = {
    # Error messages
    "knowledge_base_not_configured": "Knowledge Base not configured. Please ensure AWS resources are properly deployed and environment variables are configured.",
    "knowledge_base_empty": "There are no documents in the knowledge base yet. Please upload relevant documents first, then perform queries.",
    "upload_instructions": """You can upload documents in the following ways:
1. Use the 'Document Management' feature on the left side of the page
2. Drag and drop PDF, TXT or other supported documents
3. Wait for document processing to complete before querying""",
    "cannot_find_info": "Sorry, I cannot find relevant information to answer your question.",
    "service_unavailable": "Service is temporarily unavailable, please try again later.",
    "bedrock_error": "AI model service error, please try again later.",
    "auth_error": "Authentication failed: {error}",
    
    # Status messages
    "ready_no_documents": "⚠️ Knowledge base is empty! Please upload documents first. Click 'Document Management' on the left to start uploading.",
    "ready_with_documents": "✅ System is ready! {count} documents have been indexed and queries can begin.",
    "processing_documents": "⏳ Documents are being processed, please wait...",
    "indexing_failed": "❌ Recent indexing task failed, some documents may not be queryable.",
    "health_check_ok": "Service is healthy",
    "system_not_ready": "System not ready",
    
    # Debug messages
    "query_knowledge_base_log": "Query Knowledge Base: {kb_id}, Question: {question}",
    "kb_not_found_log": "No relevant documents found in Knowledge Base. KB_ID: {kb_id}",
    "query_complete_log": "Knowledge Base query completed, time: {time:.2f}s, sources count: {sources}",
    "error_log": "Knowledge Base query failed - Type: {error_type}, Message: {error_msg}",
    
    # Document related
    "unknown_document": "Unknown document",
    
    # Health check
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
    Get message text
    
    Args:
        key: Message key
        **kwargs: Format parameters
        
    Returns:
        Formatted message text
    """
    message = MESSAGES.get(key, key)
    if isinstance(message, str) and kwargs:
        return message.format(**kwargs)
    return message

def get_knowledge_base_empty_response() -> str:
    """Get complete response message when knowledge base is empty"""
    return f"{MESSAGES['knowledge_base_empty']}\n\n{MESSAGES['upload_instructions']}"