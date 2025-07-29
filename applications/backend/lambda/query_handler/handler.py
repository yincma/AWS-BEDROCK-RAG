"""
AWS Lambda Query Handler
System Two: Enterprise-grade RAG Knowledge Q&A System based on AWS Nova
"""

import json
import logging
import os
import time
import boto3
from typing import Dict, Any, List

# Import message configuration
try:
    from messages import get_message, get_knowledge_base_empty_response
except ImportError:
    # If import fails, define simple fallback functions
    def get_message(key: str, **kwargs) -> str:
        messages = {
            "knowledge_base_not_configured": "Knowledge Base not configured. Please ensure AWS resources are properly deployed and environment variables are configured.",
            "knowledge_base_empty": "There are no documents in the knowledge base yet. Please upload relevant documents first, then perform queries.",
            "cannot_find_info": "Sorry, I cannot find relevant information to answer your question.",
            "unknown_document": "Unknown document",
        }
        message = messages.get(key, key)
        if kwargs:
            return message.format(**kwargs)
        return message
    
    def get_knowledge_base_empty_response() -> str:
        return "There are no documents in the knowledge base yet. Please upload relevant documents first, then perform queries.\n\nYou can upload documents in the following ways:\n1. Use the 'Document Management' feature on the left side of the page\n2. Drag and drop PDF, TXT or other supported documents\n3. Wait for document processing to complete before querying"

# 导入共享的Lambda基类
try:
    from shared.lambda_base import cors_handler
except ImportError:
    # 备用实现
    def cors_handler(func):
        return func

# 导入共享的CORS工具函数
try:
    from shared.utils.cors import create_error_response, create_success_response
except ImportError:
    # 如果导入失败，定义简单的回退函数
    def create_success_response(data: Any, status_code: int = 200) -> Dict[str, Any]:
        return {
            "statusCode": status_code,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
                "Access-Control-Allow-Headers": "Content-Type, Authorization"
            },
            "body": json.dumps(data, ensure_ascii=False, default=str)
        }
    
    def create_error_response(status_code: int, message: str) -> Dict[str, Any]:
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

# 导入配置管理（如果可用）
try:
    from shared.config import get_config
    config = get_config()
    log_level = config.features.log_level
except ImportError:
    logger.warning("Cannot import configuration module, using environment variables")
    config = None
    log_level = os.getenv('LOG_LEVEL', 'INFO')

logger.setLevel(getattr(logging, log_level.upper(), logging.INFO))

# 获取AWS区域配置
if config:
    aws_config = {'region_name': config.region}
else:
    # 使用环境变量，如果都没有设置则让boto3使用默认行为
    region = os.environ.get('REGION') or os.environ.get('AWS_REGION')
    aws_config = {'region_name': region} if region else {}

# AWS客户端（使用正确的区域配置）
bedrock_runtime = boto3.client('bedrock-runtime', **aws_config)
bedrock_agent_runtime = boto3.client('bedrock-agent-runtime', **aws_config)
s3_client = boto3.client('s3', **aws_config)

@cors_handler
def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda函数主处理器
    
    Args:
        event: API Gateway事件
        context: Lambda上下文
        
    Returns:
        HTTP响应
    """
    try:
        logger.info(f"收到请求: {json.dumps(event, default=str)}")
        
        # 解析请求
        if 'body' in event and event['body']:
            try:
                body = json.loads(event['body'])
                logger.info(f"解析后的请求体: {json.dumps(body, ensure_ascii=False)}")
            except json.JSONDecodeError as e:
                logger.error(f"JSON解析失败: {str(e)}, Body: {event.get('body', '')[:200]}")
                return create_error_response(400, "无效的JSON格式")
        else:
            body = {}
            logger.warning("请求中没有body")
        
        # 处理不同的HTTP方法和路径
        http_method = event.get('httpMethod', 'GET')
        path = event.get('path', '/')
        
        # 处理CORS预检请求
        if http_method == 'OPTIONS':
            return handle_options_request()
        elif http_method == 'POST' and path.endswith('/query'):
            # 处理查询请求
            return handle_query_request(body)
        elif http_method == 'GET' and path.endswith('/query'):
            # 处理健康检查
            return handle_health_check()
        elif http_method == 'GET' and path.endswith('/status'):
            # 处理知识库状态请求
            return handle_knowledge_base_status()
        else:
            return create_error_response(405, "不支持的HTTP方法")
    
    except Exception as e:
        logger.error(f"处理请求时发生错误: {str(e)}", exc_info=True)
        # 返回更详细的错误信息以便调试
        error_details = {
            "error": str(e),
            "error_type": type(e).__name__,
            "environment": {
                "KNOWLEDGE_BASE_ID": os.environ.get('KNOWLEDGE_BASE_ID', 'NOT_SET'),
                "AWS_REGION": os.environ.get('REGION', os.environ.get('AWS_REGION', 'NOT_SET')),
                "BEDROCK_MODEL_ID": os.environ.get('BEDROCK_MODEL_ID', 'NOT_SET')
            }
        }
        return create_error_response(500, f"内部服务器错误: {json.dumps(error_details)}")

def handle_query_request(body: Dict[str, Any]) -> Dict[str, Any]:
    """
    处理查询请求
    
    Args:
        body: 请求体
        
    Returns:
        查询响应
    """
    try:
        # 提取查询参数
        question = body.get('question', '').strip()
        if not question:
            return create_error_response(400, "问题不能为空")
        
        top_k = body.get('top_k', 5)
        include_sources = body.get('include_sources', True)
        
        logger.info(f"处理查询: {question}")
        
        # 调用Bedrock进行查询
        response = query_bedrock_knowledge_base(question, top_k)
        
        # 格式化响应
        result = {
            "success": True,
            "question": question,
            "answer": response.get('answer', ''),
            "sources": response.get('sources', []) if include_sources else [],
            "metadata": {
                "top_k": top_k,
                "model_used": os.environ.get('BEDROCK_MODEL_ID', 'amazon.nova-pro-v1:0'),
                "processing_time": response.get('processing_time', 0)
            }
        }
        
        return create_success_response(result)
    
    except Exception as e:
        logger.error(f"查询处理失败: {str(e)}", exc_info=True)
        # 返回更详细的错误信息
        error_details = {
            "error": str(e),
            "error_type": type(e).__name__,
            "question": question,
            "environment": {
                "KNOWLEDGE_BASE_ID": os.environ.get('KNOWLEDGE_BASE_ID', 'NOT_SET'),
                "AWS_REGION": os.environ.get('REGION', os.environ.get('AWS_REGION', 'NOT_SET')),
                "BEDROCK_MODEL_ID": os.environ.get('BEDROCK_MODEL_ID', 'NOT_SET')
            }
        }
        return create_error_response(500, f"查询处理失败: {json.dumps(error_details)}")

def query_bedrock_knowledge_base(question: str, top_k: int = 5) -> Dict[str, Any]:
    """
    查询Bedrock知识库
    
    Args:
        question: 用户问题
        top_k: 返回结果数量
        
    Returns:
        查询结果
    """
    try:
        start_time = time.time()
        
        knowledge_base_id = os.environ.get('KNOWLEDGE_BASE_ID')
        data_source_id = os.environ.get('DATA_SOURCE_ID')
        model_id = os.environ.get('BEDROCK_MODEL_ID', 'amazon.nova-pro-v1:0')
        region = os.environ.get('REGION', os.environ.get('AWS_REGION', 'unknown'))
        
        logger.info(f"环境变量检查 - KB_ID: {knowledge_base_id}, DS_ID: {data_source_id}, Model: {model_id}, Region: {region}")
        
        if not knowledge_base_id or knowledge_base_id == '':
            logger.error(f"Knowledge Base ID未配置或为空。当前值: '{knowledge_base_id}'")
            error_msg = get_message("knowledge_base_not_configured")
            return _create_fallback_response(question, start_time, error_msg)
        
        logger.info(f"查询Knowledge Base: {knowledge_base_id}, 问题: {question}")
        
        # 使用Bedrock Knowledge Base进行检索增强生成
        response = bedrock_agent_runtime.retrieve_and_generate(
            input={
                'text': question
            },
            retrieveAndGenerateConfiguration={
                'type': 'KNOWLEDGE_BASE',
                'knowledgeBaseConfiguration': {
                    'knowledgeBaseId': knowledge_base_id,
                    'modelArn': f'arn:aws:bedrock:{os.environ.get("REGION", os.environ.get("AWS_REGION"))}::foundation-model/{model_id}',
                    'retrievalConfiguration': {
                        'vectorSearchConfiguration': {
                            'numberOfResults': top_k
                        }
                    }
                }
            }
        )
        
        processing_time = time.time() - start_time
        
        # 提取生成的答案
        output = response.get('output', {})
        answer = output.get('text', get_message("cannot_find_info"))
        
        # 提取来源信息
        sources = []
        citations = response.get('citations', [])
        
        for citation in citations:
            retrieved_references = citation.get('retrievedReferences', [])
            for ref in retrieved_references:
                content = ref.get('content', {})
                location = ref.get('location', {})
                
                source_info = {
                    'content': content.get('text', ''),
                    'document': location.get('s3Location', {}).get('uri', get_message("unknown_document")),
                    'confidence': ref.get('metadata', {}).get('score', 0.0)
                }
                sources.append(source_info)
        
        # 检查是否没有找到任何文档
        if len(sources) == 0:
            logger.warning(f"Knowledge Base中没有找到相关文档。KB_ID: {knowledge_base_id}")
            # 检查答案是否为默认的"无法找到信息"类型的回复
            if "无法找到相关信息" in answer or "I cannot find" in answer or len(answer) < 50:
                return {
                    "answer": get_knowledge_base_empty_response(),
                    "sources": [],
                    "processing_time": processing_time,
                    "citations_count": 0,
                    "model_used": model_id,
                    "no_documents": True
                }
        
        result = {
            "answer": answer,
            "sources": sources,
            "processing_time": processing_time,
            "citations_count": len(citations),
            "model_used": model_id
        }
        
        logger.info(f"Knowledge Base查询完成，耗时: {processing_time:.2f}秒，来源数量: {len(sources)}")
        return result
    
    except Exception as e:
        error_type = type(e).__name__
        error_msg = str(e)
        logger.error(f"Knowledge Base查询失败 - 类型: {error_type}, 消息: {error_msg}", exc_info=True)
        
        # 提供更详细的错误信息
        if "ResourceNotFoundException" in error_type or "ResourceNotFound" in error_msg:
            detailed_error = f"Knowledge Base ({knowledge_base_id}) 不存在或无法访问。请检查部署状态。"
        elif "AccessDeniedException" in error_type or "AccessDenied" in error_msg:
            detailed_error = "权限不足：Lambda函数无法访问Knowledge Base。请检查IAM权限。"
        elif "ValidationException" in error_type:
            detailed_error = "请求参数无效。请检查Knowledge Base配置。"
        else:
            detailed_error = f"查询失败: {error_msg}"
            
        return _create_fallback_response(question, start_time, detailed_error)

def _create_fallback_response(question: str, start_time: float, error_msg: str = None) -> Dict[str, Any]:
    """
    创建备用响应（当Knowledge Base不可用时）
    """
    try:
        logger.info("使用备用模式：直接调用Bedrock模型")
        
        model_id = os.environ.get('BEDROCK_MODEL_ID', 'amazon.nova-pro-v1:0')
        
        # 构建提示词
        prompt = f"""请基于你的知识回答以下问题。如果你不确定答案，请诚实地说明。

问题: {question}

请提供准确、有用的回答："""
        
        # 调用Bedrock模型
        if 'nova' in model_id.lower():
            # Nova模型格式
            body = {
                "inputText": prompt,
                "textGenerationConfig": {
                    "maxTokenCount": 1000,
                    "temperature": 0.1,
                    "topP": 0.9
                }
            }
        else:
            # 其他模型格式
            body = {
                "prompt": prompt,
                "max_tokens": 1000,
                "temperature": 0.1,
                "top_p": 0.9
            }
        
        response = bedrock_runtime.invoke_model(
            modelId=model_id,
            body=json.dumps(body)
        )
        
        response_body = json.loads(response['body'].read())
        
        # 解析响应（根据模型类型）
        if 'nova' in model_id.lower():
            answer = response_body.get('results', [{}])[0].get('outputText', '抱歉，我无法回答您的问题。')
        else:
            answer = response_body.get('completion', '抱歉，我无法回答您的问题。')
        
        processing_time = time.time() - start_time
        
        return {
            "answer": f"{answer}\n\n⚠️ 注意：此回答基于模型的一般知识，未使用企业知识库。" + (f" 错误信息: {error_msg}" if error_msg else ""),
            "sources": [],
            "processing_time": processing_time,
            "citations_count": 0,
            "model_used": model_id,
            "fallback_mode": True
        }
    
    except Exception as fallback_error:
        logger.error(f"备用模式也失败了: {str(fallback_error)}")
        return {
            "answer": "抱歉，服务暂时不可用，请稍后再试。",
            "sources": [],
            "processing_time": time.time() - start_time,
            "citations_count": 0,
            "error": True
        }

def handle_options_request() -> Dict[str, Any]:
    """
    处理CORS预检请求
    
    Returns:
        CORS预检响应
    """
    return {
        "statusCode": 200,
        "headers": {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type, X-Amz-Date, Authorization, X-Api-Key, X-Amz-Security-Token",
            "Access-Control-Max-Age": "86400"  # 24小时缓存预检结果
        },
        "body": ""
    }

def handle_health_check() -> Dict[str, Any]:
    """
    处理健康检查请求
    
    Returns:
        健康检查响应
    """
    health_status = {
        "status": "healthy",
        "service": "RAG Query Handler",
        "version": "2.0.0",
        "timestamp": str(int(time.time())),
        "environment": os.environ.get('ENVIRONMENT', 'unknown'),
        "region": os.environ.get('REGION', os.environ.get('AWS_REGION', 'unknown')),
        "knowledge_base_id": os.environ.get('KNOWLEDGE_BASE_ID', 'not_configured'),
        "checks": {
            "bedrock": check_bedrock_availability(),
            "knowledge_base": check_knowledge_base_availability(),
            "s3": check_s3_availability()
        }
    }
    
    # 检查所有服务是否正常
    all_healthy = all(check["status"] == "ok" for check in health_status["checks"].values())
    if not all_healthy:
        health_status["status"] = "degraded"
    
    return create_success_response(health_status)

def check_bedrock_availability() -> Dict[str, Any]:
    """检查Bedrock服务可用性"""
    try:
        # 尝试列出模型来测试连接
        bedrock_client = boto3.client('bedrock', **aws_config)
        models = bedrock_client.list_foundation_models(maxResults=1)
        
        return {
            "status": "ok",
            "message": "Bedrock服务可用",
            "models_available": len(models.get('modelSummaries', []))
        }
    except Exception as e:
        return {
            "status": "error",
            "message": f"Bedrock服务不可用: {str(e)}"
        }

def check_knowledge_base_availability() -> Dict[str, Any]:
    """检查Knowledge Base可用性"""
    try:
        knowledge_base_id = os.environ.get('KNOWLEDGE_BASE_ID')
        if not knowledge_base_id:
            return {
                "status": "warning",
                "message": "Knowledge Base ID未配置"
            }
        
        # 尝试获取Knowledge Base信息
        bedrock_agent = boto3.client('bedrock-agent', **aws_config)
        kb_info = bedrock_agent.get_knowledge_base(knowledgeBaseId=knowledge_base_id)
        
        status = kb_info.get('knowledgeBase', {}).get('status', 'UNKNOWN')
        
        return {
            "status": "ok" if status == "ACTIVE" else "warning",
            "message": f"Knowledge Base状态: {status}",
            "knowledge_base_id": knowledge_base_id,
            "kb_status": status
        }
    except Exception as e:
        return {
            "status": "error",
            "message": f"Knowledge Base不可用: {str(e)}"
        }

def check_s3_availability() -> Dict[str, Any]:
    """检查S3服务可用性"""
    try:
        bucket_name = os.environ.get('S3_BUCKET')
        if not bucket_name:
            return {
                "status": "warning",
                "message": "S3存储桶未配置"
            }
        
        # 检查存储桶是否存在
        s3_client.head_bucket(Bucket=bucket_name)
        
        return {
            "status": "ok",
            "message": "S3服务可用",
            "bucket": bucket_name
        }
    except Exception as e:
        return {
            "status": "error",
            "message": f"S3服务不可用: {str(e)}"
        }

def create_success_response(data: Any, status_code: int = 200) -> Dict[str, Any]:
    """
    创建成功响应
    
    Args:
        data: 响应数据
        status_code: HTTP状态码
        
    Returns:
        API Gateway响应格式
    """
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type, Authorization"
        },
        "body": json.dumps(data, ensure_ascii=False, default=str)
    }

def handle_knowledge_base_status() -> Dict[str, Any]:
    """
    处理知识库状态请求
    
    Returns:
        知识库状态响应
    """
    try:
        bedrock_agent = boto3.client('bedrock-agent', **aws_config)
        
        knowledge_base_id = os.environ.get('KNOWLEDGE_BASE_ID')
        data_source_id = os.environ.get('DATA_SOURCE_ID')
        
        logger.info(f"获取知识库状态 - KB_ID: {knowledge_base_id}, DS_ID: {data_source_id}")
        
        if not knowledge_base_id or not data_source_id:
            return create_error_response(500, "Knowledge Base未配置")
        
        # 获取Knowledge Base状态
        kb_response = bedrock_agent.get_knowledge_base(knowledgeBaseId=knowledge_base_id)
        kb_status = kb_response.get('knowledgeBase', {}).get('status', 'UNKNOWN')
        kb_name = kb_response.get('knowledgeBase', {}).get('name', 'N/A')
        
        # 获取最新的摄入任务
        jobs_response = bedrock_agent.list_ingestion_jobs(
            knowledgeBaseId=knowledge_base_id,
            dataSourceId=data_source_id,
            maxResults=10  # 增加获取数量以便更准确判断
        )
        
        jobs = []
        latest_job = None  # 真正的最新任务
        total_documents_indexed = 0
        has_any_documents = False
        
        # 处理任务列表
        job_summaries = jobs_response.get('ingestionJobSummaries', [])
        
        # 找出真正的最新任务（第一个就是最新的，因为API返回已按时间倒序排序）
        if job_summaries:
            latest_job = job_summaries[0]
        
        for job in job_summaries[:5]:  # 只详细处理前5个任务
            job_id = job.get('ingestionJobId', '')
            job_status = job.get('status', 'UNKNOWN')
            
            # 获取详细信息
            try:
                job_detail = bedrock_agent.get_ingestion_job(
                    knowledgeBaseId=knowledge_base_id,
                    dataSourceId=data_source_id,
                    ingestionJobId=job_id
                )
                
                stats = job_detail.get('ingestionJob', {}).get('statistics', {})
                documents_indexed = stats.get('numberOfNewDocumentsIndexed', 0) + stats.get('numberOfModifiedDocumentsIndexed', 0)
                
                job_info = {
                    'id': job_id,
                    'status': job_status,
                    'startedAt': job.get('startedAt', '').isoformat() if hasattr(job.get('startedAt', ''), 'isoformat') else str(job.get('startedAt', '')),
                    'completedAt': job.get('completedAt', '').isoformat() if hasattr(job.get('completedAt', ''), 'isoformat') else str(job.get('completedAt', '')),
                    'documentsScanned': stats.get('numberOfDocumentsScanned', 0),
                    'documentsFailed': stats.get('numberOfDocumentsFailed', 0),
                    'documentsIndexed': documents_indexed
                }
                
                jobs.append(job_info)
                
                # 检查是否有成功索引的文档
                if job_status == 'COMPLETE' and documents_indexed > 0:
                    has_any_documents = True
                    
            except Exception as e:
                logger.warning(f"无法获取任务详情 {job_id}: {str(e)}")
                jobs.append({
                    'id': job_id,
                    'status': job_status,
                    'error': str(e)
                })
        
        # 获取最新任务的状态
        latest_job_status = latest_job.get('status', 'UNKNOWN') if latest_job else None
        
        # 尝试查询Knowledge Base中的实际文档数
        # 注意：Bedrock API没有直接获取文档总数的方法，但我们可以：
        # 1. 检查是否有任何成功的 ingestion job
        # 2. 累计所有成功任务的文档数（需要遍历更多历史任务）
        
        # 如果有任何成功的任务，我们就认为Knowledge Base中有文档
        # 实际文档数需要通过查询或其他方式获取
        if has_any_documents:
            # 简单估算：累计最近成功任务的文档数
            for job in job_summaries:
                if job.get('status') == 'COMPLETE':
                    stats = job.get('statistics', {})
                    indexed = stats.get('numberOfNewDocumentsIndexed', 0) + stats.get('numberOfModifiedDocumentsIndexed', 0)
                    if indexed > 0:
                        total_documents_indexed = max(total_documents_indexed, stats.get('numberOfDocumentsScanned', 0))
        
        # 确定系统是否就绪
        system_ready = False
        ready_message = get_message("system_not_ready")
        
        if kb_status == 'ACTIVE':
            if not job_summaries:
                ready_message = get_message("ready_no_documents")
                system_ready = False
            elif latest_job_status == 'COMPLETE':
                # 最新任务成功
                if has_any_documents or total_documents_indexed > 0:
                    system_ready = True
                    ready_message = get_message("ready_with_documents", count=total_documents_indexed if total_documents_indexed > 0 else "多个")
                else:
                    ready_message = get_message("ready_no_documents")
                    system_ready = False
            elif latest_job_status == 'IN_PROGRESS':
                ready_message = get_message("processing_documents")
                system_ready = False
            elif latest_job_status == 'FAILED':
                # 即使最新任务失败，如果之前有成功的任务，系统仍可用
                if has_any_documents:
                    system_ready = True
                    ready_message = "⚠️ 最新的索引任务失败，但系统中仍有可查询的文档。"
                else:
                    ready_message = get_message("indexing_failed")
                    system_ready = False
            else:
                ready_message = "⚠️ 知识库状态未知"
                system_ready = False
        else:
            ready_message = f"⚠️ Knowledge Base状态异常: {kb_status}"
        
        # 构建响应
        status_response = {
            "success": True,
            "knowledgeBase": {
                "id": knowledge_base_id,
                "name": kb_name,
                "status": kb_status,
                "dataSourceId": data_source_id
            },
            "systemReady": system_ready,
            "readyMessage": ready_message,
            "hasDocuments": has_any_documents,
            "ingestionJobs": jobs,
            "summary": {
                "latestJobStatus": latest_job_status,
                "totalDocumentsIndexed": total_documents_indexed,
                "totalJobs": len(job_summaries),
                "hasAnySuccessfulJobs": has_any_documents
            },
            "timestamp": str(int(time.time()))
        }
        
        logger.info(f"知识库状态: ready={system_ready}, latest_job={latest_job_status}, has_docs={has_any_documents}")
        
        return create_success_response(status_response)
        
    except Exception as e:
        logger.error(f"获取Knowledge Base状态失败: {str(e)}", exc_info=True)
        return create_error_response(500, f"获取状态失败: {str(e)}")

def create_error_response(status_code: int, message: str) -> Dict[str, Any]:
    """
    创建错误响应
    
    Args:
        status_code: HTTP状态码
        message: 错误消息
        
    Returns:
        API Gateway错误响应格式
    """
    error_response = {
        "success": False,
        "error": {
            "code": status_code,
            "message": message
        },
        "timestamp": str(int(time.time()))
    }
    
    return create_success_response(error_response, status_code)