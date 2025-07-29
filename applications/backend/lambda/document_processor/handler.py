"""
AWS Lambda Document Processor
System Two: Enterprise-grade RAG Knowledge Q&A System based on AWS Nova
"""

import json
import logging
import os
import time
import boto3
import uuid
from typing import Dict, Any

# Import configuration management
try:
    from shared.config import get_config
    config = get_config()
except ImportError:
    logger = logging.getLogger()
    logger.warning("Cannot import configuration module, using environment variables")
    config = None

# Import shared Lambda base class
try:
    from shared.lambda_base import cors_handler
except ImportError:
    # Fallback implementation
    def cors_handler(func):
        return func

# Import shared CORS utility functions
try:
    from shared.utils.cors import create_error_response, create_success_response
except ImportError:
    # If import fails, immediately define fallback functions
    import json
    
    def create_success_response(data, status_code=200):
        """Create success response (fallback implementation)"""
        headers = config.get_cors_headers() if config else {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": os.getenv('CORS_ALLOW_ORIGIN', '*'),
            "Access-Control-Allow-Methods": os.getenv('CORS_ALLOW_METHODS', 'GET,POST,OPTIONS'),
            "Access-Control-Allow-Headers": os.getenv('CORS_ALLOW_HEADERS', 'Content-Type,Authorization')
        }
        return {
            "statusCode": status_code,
            "headers": headers,
            "body": json.dumps(data, ensure_ascii=False, default=str)
        }
    
    def create_error_response(status_code, message):
        """创建错误响应（备用实现）"""
        error_response = {
            "success": False,
            "error": {
                "code": status_code,
                "message": message
            },
            "timestamp": str(int(time.time()))
        }
        return create_success_response(error_response, status_code)

# 配置日志
logger = logging.getLogger()
log_level = config.features.log_level if config else os.getenv('LOG_LEVEL', 'INFO')
logger.setLevel(getattr(logging, log_level.upper(), logging.INFO))

# 获取AWS配置
if config:
    aws_config = {'region_name': config.region}
else:
    aws_config = {'region_name': os.environ.get('REGION', os.environ.get('AWS_REGION', 'us-east-1'))}

# AWS客户端
s3_client = boto3.client('s3', **aws_config)
bedrock_agent = boto3.client('bedrock-agent', **aws_config)

@cors_handler
def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda函数主处理器
    
    Args:
        event: API Gateway事件或S3事件
        context: Lambda上下文
        
    Returns:
        HTTP响应
    """
    try:
        logger.info(f"收到事件: {json.dumps(event, default=str)}")
        
        # 判断事件类型
        if 'httpMethod' in event:
            # API Gateway事件 - 根据HTTP方法和路径处理不同请求
            http_method = event.get('httpMethod', '')
            resource_path = event.get('resource', '')
            
            if resource_path == '/upload' and http_method == 'POST':
                return handle_upload_request(event)
            elif resource_path == '/documents' and http_method == 'GET':
                return handle_documents_list_request(event)
            else:
                return create_error_response(400, f"不支持的请求: {http_method} {resource_path}")
        elif 'Records' in event and event['Records'][0].get('eventSource') == 'aws:s3':
            # S3事件 - 处理文档上传后的处理
            return handle_s3_event(event)
        else:
            return create_error_response(400, "不支持的事件类型")
    
    except Exception as e:
        logger.error(f"处理请求时发生错误: {str(e)}", exc_info=True)
        return create_error_response(500, "内部服务器错误")

def handle_upload_request(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    处理文档上传请求，生成预签名URL
    
    Args:
        event: API Gateway事件
        
    Returns:
        包含预签名URL的响应
    """
    try:
        # 解析请求体
        if 'body' in event and event['body']:
            body = json.loads(event['body'])
        else:
            return create_error_response(400, "请求体不能为空")
        
        # 提取文件信息
        filename = body.get('filename', '').strip()
        content_type = body.get('contentType', 'application/octet-stream')
        file_size = body.get('fileSize', 0)
        
        if not filename:
            return create_error_response(400, "文件名不能为空")
        
        # 验证文件类型
        if config:
            if not config.document.validate_file_extension(filename):
                allowed_extensions = config.document.allowed_file_extensions
                return create_error_response(400, f"不支持的文件类型。支持的类型: {', '.join(allowed_extensions)}")
        else:
            # 备用验证（使用环境变量）
            allowed_extensions = os.getenv('ALLOWED_FILE_EXTENSIONS', '.pdf,.txt,.docx,.doc,.md,.csv,.json').split(',')
            if not any(filename.lower().endswith(ext) for ext in allowed_extensions):
                return create_error_response(400, f"不支持的文件类型。支持的类型: {', '.join(allowed_extensions)}")
        
        # 验证文件大小
        if config:
            if not config.document.validate_file_size(file_size):
                max_size_mb = config.document.max_file_size_mb
                return create_error_response(400, f"文件大小超过限制 ({max_size_mb}MB)")
        else:
            # 备用验证（使用环境变量）
            max_size_mb = int(os.getenv('MAX_FILE_SIZE_MB', '100'))
            max_size = max_size_mb * 1024 * 1024
            if file_size > max_size:
                return create_error_response(400, f"文件大小超过限制 ({max_size_mb}MB)")
        
        # 生成唯一的文件名
        file_id = str(uuid.uuid4())
        file_extension = filename[filename.rfind('.'):]
        
        # 生成S3键
        if config:
            s3_key = config.get_s3_key(file_id, file_extension)
        else:
            document_prefix = os.getenv('DOCUMENT_PREFIX', 'documents/')
            s3_key = f"{document_prefix}{file_id}{file_extension}"
        
        # 获取S3存储桶名称
        bucket_name = config.s3.document_bucket if config else os.environ.get('S3_BUCKET')
        if not bucket_name:
            return create_error_response(500, "S3存储桶未配置")
        
        # 生成预签名URL
        # 获取过期时间配置
        expiry_seconds = config.document.presigned_url_expiry_seconds if config else int(os.getenv('PRESIGNED_URL_EXPIRY_SECONDS', '900'))
        
        # 注意：移除Metadata以简化上传过程，避免编码问题
        presigned_url = s3_client.generate_presigned_url(
            'put_object',
            Params={
                'Bucket': bucket_name,
                'Key': s3_key,
                'ContentType': content_type
            },
            ExpiresIn=expiry_seconds
        )
        
        # 添加调试日志
        logger.info(f"生成的预签名URL参数: Bucket={bucket_name}, Key={s3_key}, ContentType={content_type}")
        
        # 构建响应 - 包含success字段和直接的数据
        result = {
            "success": True,
            "uploadUrl": presigned_url,
            "fileId": file_id,
            "s3Key": s3_key,
            "bucket": bucket_name,
            "expiresIn": expiry_seconds,
            "message": f"预签名URL生成成功，请在{expiry_seconds // 60}分钟内完成上传"
        }
        
        logger.info(f"为文件 {filename} 生成预签名URL成功: {s3_key}")
        
        # 直接返回result，避免双重嵌套
        return create_success_response(result)
    
    except Exception as e:
        logger.error(f"生成预签名URL失败: {str(e)}", exc_info=True)
        return create_error_response(500, f"生成上传URL失败: {str(e)}")

def handle_documents_list_request(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    处理获取文档列表请求
    
    Args:
        event: API Gateway事件
        
    Returns:
        包含文档列表的响应
    """
    try:
        # 记录开始处理文档列表请求
        logger.info("开始处理文档列表请求")
        
        # 记录配置信息（用于调试）
        if config:
            logger.info(f"使用配置模块: {config.get_config_summary()}")
        else:
            logger.info(f"环境变量: S3_BUCKET={os.environ.get('S3_BUCKET')}, "
                        f"KNOWLEDGE_BASE_ID={os.environ.get('KNOWLEDGE_BASE_ID')}, "
                        f"DATA_SOURCE_ID={os.environ.get('DATA_SOURCE_ID')}")
        
        # 获取S3存储桶名称
        bucket_name = config.s3.document_bucket if config else os.environ.get('S3_BUCKET')
        if not bucket_name:
            logger.error("S3存储桶未配置")
            return create_error_response(500, "S3存储桶未配置")
        
        # 获取文档前缀
        document_prefix = config.s3.document_prefix if config else os.getenv('DOCUMENT_PREFIX', 'documents/')
        
        # 列出S3存储桶中的文档
        response = s3_client.list_objects_v2(
            Bucket=bucket_name,
            Prefix=document_prefix
        )
        
        documents = []
        if 'Contents' in response:
            for obj in response['Contents']:
                # 跳过文件夹
                if obj['Key'].endswith('/'):
                    continue
                    
                # 获取文件元数据
                try:
                    metadata_response = s3_client.head_object(
                        Bucket=bucket_name,
                        Key=obj['Key']
                    )
                    metadata = metadata_response.get('Metadata', {})
                    
                    # 提取文件ID
                    file_id = metadata.get('file-id', obj['Key'].split('/')[-1].split('.')[0])
                    original_filename = metadata.get('original-filename', obj['Key'].split('/')[-1])
                    
                    document = {
                        "id": file_id,
                        "name": original_filename,
                        "size": obj['Size'],
                        "type": metadata.get('content-type', 'application/octet-stream'),
                        "upload_date": obj['LastModified'].isoformat(),
                        "processed_date": None,
                        "status": "active",
                        "s3_key": obj['Key'],
                        "metadata": {
                            "original_filename": original_filename,
                            "content_type": metadata.get('content-type'),
                            "file_size": obj['Size']
                        }
                    }
                    documents.append(document)
                    
                except Exception as e:
                    logger.warning(f"无法获取文件元数据 {obj['Key']}: {str(e)}")
                    continue
        
        # 构建响应
        result = {
            "success": True,
            "data": documents,
            "metadata": {
                "total": len(documents),
                "timestamp": str(int(time.time()))
            }
        }
        
        logger.info(f"返回文档列表，共 {len(documents)} 个文档")
        return create_success_response(result)
    
    except Exception as e:
        logger.error(f"获取文档列表失败: {str(e)}", exc_info=True)
        return create_error_response(500, f"获取文档列表失败: {str(e)}")

def handle_s3_event(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    处理S3上传事件，触发文档处理流程
    
    Args:
        event: S3事件
        
    Returns:
        处理结果
    """
    try:
        processed_files = []
        
        for record in event['Records']:
            bucket = record['s3']['bucket']['name']
            key = record['s3']['object']['key']
            
            logger.info(f"处理S3对象: s3://{bucket}/{key}")
            
            # 触发Knowledge Base数据源同步
            result = trigger_knowledge_base_sync(key)
            
            processed_files.append({
                "bucket": bucket,
                "key": key,
                "syncResult": result
            })
        
        return create_success_response({
            "message": "文档处理完成",
            "processedFiles": processed_files
        })
    
    except Exception as e:
        logger.error(f"S3事件处理失败: {str(e)}", exc_info=True)
        return create_error_response(500, f"文档处理失败: {str(e)}")

def trigger_knowledge_base_sync(s3_key: str) -> Dict[str, Any]:
    """
    触发Knowledge Base数据源同步
    
    Args:
        s3_key: S3对象键
        
    Returns:
        同步结果
    """
    try:
        # 获取Knowledge Base配置
        if config:
            knowledge_base_id = config.bedrock.knowledge_base_id
            data_source_id = config.bedrock.data_source_id
        else:
            knowledge_base_id = os.environ.get('KNOWLEDGE_BASE_ID')
            data_source_id = os.environ.get('DATA_SOURCE_ID')
        
        if not knowledge_base_id or not data_source_id:
            logger.warning("Knowledge Base ID或Data Source ID未配置，跳过同步")
            return {
                "status": "skipped",
                "reason": "Knowledge Base未配置"
            }
        
        # 启动数据源同步任务
        response = bedrock_agent.start_ingestion_job(
            knowledgeBaseId=knowledge_base_id,
            dataSourceId=data_source_id,
            description=f"自动同步文档: {s3_key}"
        )
        
        job_id = response.get('ingestionJob', {}).get('ingestionJobId')
        
        logger.info(f"Knowledge Base同步任务已启动: {job_id}")
        
        return {
            "status": "started",
            "jobId": job_id,
            "knowledgeBaseId": knowledge_base_id,
            "dataSourceId": data_source_id
        }
    
    except Exception as e:
        logger.error(f"启动Knowledge Base同步失败: {str(e)}")
        return {
            "status": "failed",
            "error": str(e)
        }

# 这些函数已经在文件开头定义为备用实现
