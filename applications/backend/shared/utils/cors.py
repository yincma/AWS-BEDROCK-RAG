"""
CORS 工具函数
为 Lambda 函数响应添加 CORS headers
"""

from typing import Dict, Any, Optional

def add_cors_headers(response: Dict[str, Any], 
                    origin: str = "*",
                    methods: str = "GET,POST,PUT,DELETE,OPTIONS",
                    headers: str = "Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token",
                    credentials: bool = False) -> Dict[str, Any]:
    """
    为 Lambda 响应添加 CORS headers
    
    Args:
        response: Lambda 响应字典，必须包含 statusCode 和 body
        origin: 允许的源，默认为 "*"
        methods: 允许的 HTTP 方法
        headers: 允许的请求头
        credentials: 是否允许携带凭证
        
    Returns:
        包含 CORS headers 的响应
    """
    if 'headers' not in response:
        response['headers'] = {}
    
    # 添加 CORS headers
    response['headers']['Access-Control-Allow-Origin'] = origin
    response['headers']['Access-Control-Allow-Methods'] = methods
    response['headers']['Access-Control-Allow-Headers'] = headers
    
    if credentials and origin != "*":
        response['headers']['Access-Control-Allow-Credentials'] = 'true'
    
    return response


def create_response(status_code: int, 
                   body: Any,
                   error: Optional[str] = None,
                   cors_enabled: bool = True) -> Dict[str, Any]:
    """
    创建标准的 Lambda 响应，包含 CORS headers
    
    Args:
        status_code: HTTP 状态码
        body: 响应体内容
        error: 错误消息（如果有）
        cors_enabled: 是否启用 CORS
        
    Returns:
        Lambda 响应字典
    """
    import json
    
    # 构建响应体
    if error:
        response_body = {"error": error}
    else:
        response_body = body if isinstance(body, dict) else {"data": body}
    
    # 创建基本响应
    response = {
        "statusCode": status_code,
        "body": json.dumps(response_body, ensure_ascii=False)
    }
    
    # 添加 CORS headers
    if cors_enabled:
        response = add_cors_headers(response)
    
    return response


def create_error_response(status_code: int, 
                         error_message: str,
                         cors_enabled: bool = True) -> Dict[str, Any]:
    """
    创建错误响应
    
    Args:
        status_code: HTTP 状态码
        error_message: 错误消息
        cors_enabled: 是否启用 CORS
        
    Returns:
        Lambda 错误响应
    """
    return create_response(
        status_code=status_code,
        body=None,
        error=error_message,
        cors_enabled=cors_enabled
    )


def create_success_response(data: Any,
                           cors_enabled: bool = True) -> Dict[str, Any]:
    """
    创建成功响应
    
    Args:
        data: 响应数据
        cors_enabled: 是否启用 CORS
        
    Returns:
        Lambda 成功响应
    """
    return create_response(
        status_code=200,
        body=data,
        error=None,
        cors_enabled=cors_enabled
    )