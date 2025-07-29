import json
import logging
from typing import Dict, Any
from functools import wraps

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def cors_handler(func):
    """统一的CORS处理装饰器"""
    @wraps(func)
    def wrapper(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
        # CORS响应头
        cors_headers = {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token",
            "Content-Type": "application/json"
        }
        
        try:
            # 处理OPTIONS预检请求
            if event.get('httpMethod') == 'OPTIONS':
                return {
                    "statusCode": 200,
                    "headers": cors_headers,
                    "body": ""
                }
            
            # 调用实际处理函数
            result = func(event, context)
            
            # 确保响应包含CORS头
            if isinstance(result, dict) and 'statusCode' in result:
                if 'headers' not in result:
                    result['headers'] = {}
                result['headers'].update(cors_headers)
                return result
            else:
                # 如果返回的不是标准响应格式，包装成标准格式
                return {
                    "statusCode": 200,
                    "headers": cors_headers,
                    "body": json.dumps(result, ensure_ascii=False)
                }
                
        except Exception as e:
            logger.error(f"Lambda处理失败: {str(e)}", exc_info=True)
            return {
                "statusCode": 500,
                "headers": cors_headers,
                "body": json.dumps({"error": str(e)}, ensure_ascii=False)
            }
    
    return wrapper