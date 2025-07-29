"""
优化的Lambda处理器基类
实现冷启动优化、连接池复用、缓存等性能优化措施
"""
import json
import logging
import os
import time
from functools import lru_cache, wraps
from typing import Dict, Any, Optional, Callable
import boto3
from botocore.config import Config

# 配置日志（在Lambda容器外初始化）
logger = logging.getLogger()
logger.setLevel(os.getenv('LOG_LEVEL', 'INFO'))

# 全局客户端缓存（减少冷启动时间）
_clients_cache = {}

# AWS客户端配置
AWS_CONFIG = Config(
    region_name=os.getenv('AWS_REGION', 'us-east-1'),
    retries={
        'max_attempts': 3,
        'mode': 'adaptive'
    },
    max_pool_connections=50
)

def get_aws_client(service_name: str, **kwargs):
    """
    获取或创建AWS客户端（单例模式）
    使用连接池复用连接，减少延迟
    """
    cache_key = f"{service_name}:{json.dumps(kwargs, sort_keys=True)}"
    
    if cache_key not in _clients_cache:
        client_kwargs = {'config': AWS_CONFIG}
        client_kwargs.update(kwargs)
        _clients_cache[cache_key] = boto3.client(service_name, **client_kwargs)
        logger.info(f"创建新的AWS客户端: {service_name}")
    
    return _clients_cache[cache_key]

# 预加载常用客户端（在Lambda容器启动时执行）
def preload_clients():
    """预加载常用AWS客户端，减少首次请求延迟"""
    services = ['bedrock-runtime', 'bedrock-agent-runtime', 's3', 'cloudwatch']
    for service in services:
        try:
            get_aws_client(service)
        except Exception as e:
            logger.warning(f"预加载客户端失败 {service}: {e}")

# Lambda容器启动时执行
preload_clients()

class LambdaOptimizedHandler:
    """优化的Lambda处理器基类"""
    
    def __init__(self):
        # 初始化时获取所需的客户端
        self.bedrock_runtime = get_aws_client('bedrock-runtime')
        self.bedrock_agent = get_aws_client('bedrock-agent-runtime')
        self.s3 = get_aws_client('s3')
        self.cloudwatch = get_aws_client('cloudwatch')
        
        # 配置缓存
        self._config_cache = {}
        self._load_config()
    
    def _load_config(self):
        """加载并缓存配置"""
        self._config_cache = {
            'knowledge_base_id': os.getenv('KNOWLEDGE_BASE_ID'),
            'data_source_id': os.getenv('DATA_SOURCE_ID'),
            'model_id': os.getenv('BEDROCK_MODEL_ID', 'amazon.nova-pro-v1:0'),
            's3_bucket': os.getenv('S3_BUCKET'),
            'region': os.getenv('AWS_REGION', 'us-east-1')
        }
    
    @lru_cache(maxsize=1024)
    def get_cached_response(self, cache_key: str) -> Optional[Dict[str, Any]]:
        """
        内存缓存响应（适用于频繁查询）
        注意：Lambda内存有限，谨慎使用
        """
        # 这是一个占位符，实际实现需要考虑缓存失效策略
        return None
    
    def set_cached_response(self, cache_key: str, response: Dict[str, Any], ttl: int = 300):
        """设置缓存响应"""
        # 实际实现中可以使用ElastiCache或DynamoDB进行分布式缓存
        pass

def performance_monitor(metric_name: str = None):
    """
    性能监控装饰器
    自动记录函数执行时间并发送CloudWatch指标
    """
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        def wrapper(*args, **kwargs):
            start_time = time.time()
            
            try:
                result = func(*args, **kwargs)
                execution_time = (time.time() - start_time) * 1000  # 转换为毫秒
                
                # 发送性能指标
                try:
                    cloudwatch = get_aws_client('cloudwatch')
                    cloudwatch.put_metric_data(
                        Namespace='RAG-System/Performance',
                        MetricData=[
                            {
                                'MetricName': metric_name or f"{func.__name__}_duration",
                                'Value': execution_time,
                                'Unit': 'Milliseconds',
                                'Dimensions': [
                                    {
                                        'Name': 'FunctionName',
                                        'Value': os.getenv('AWS_LAMBDA_FUNCTION_NAME', 'unknown')
                                    },
                                    {
                                        'Name': 'Environment',
                                        'Value': os.getenv('ENVIRONMENT', 'dev')
                                    }
                                ]
                            }
                        ]
                    )
                except Exception as e:
                    logger.warning(f"发送性能指标失败: {e}")
                
                # 记录慢查询
                if execution_time > 3000:  # 3秒
                    logger.warning(f"慢查询检测: {func.__name__} 耗时 {execution_time:.2f}ms")
                
                return result
                
            except Exception as e:
                execution_time = (time.time() - start_time) * 1000
                logger.error(f"函数执行失败: {func.__name__}, 耗时 {execution_time:.2f}ms", exc_info=True)
                raise
        
        return wrapper
    return decorator

def batch_processor(batch_size: int = 25):
    """
    批处理装饰器
    将多个请求合并处理，提高吞吐量
    """
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        def wrapper(items: list, *args, **kwargs):
            results = []
            
            # 分批处理
            for i in range(0, len(items), batch_size):
                batch = items[i:i + batch_size]
                try:
                    batch_results = func(batch, *args, **kwargs)
                    results.extend(batch_results)
                except Exception as e:
                    logger.error(f"批处理失败 (批次 {i//batch_size + 1}): {e}")
                    # 继续处理其他批次
                    results.extend([None] * len(batch))
            
            return results
        
        return wrapper
    return decorator

class ConnectionPool:
    """
    连接池管理器
    用于管理外部服务连接（如OpenSearch）
    """
    def __init__(self, max_connections: int = 10):
        self.max_connections = max_connections
        self._connections = []
        self._available = []
    
    def get_connection(self):
        """获取可用连接"""
        if self._available:
            return self._available.pop()
        elif len(self._connections) < self.max_connections:
            conn = self._create_connection()
            self._connections.append(conn)
            return conn
        else:
            # 等待可用连接
            raise RuntimeError("连接池已满")
    
    def release_connection(self, conn):
        """释放连接回池"""
        if conn in self._connections:
            self._available.append(conn)
    
    def _create_connection(self):
        """创建新连接（子类实现）"""
        raise NotImplementedError

# 预热处理器
def warmup_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda预热处理器
    处理CloudWatch Events的预热请求
    """
    # 检查是否是预热请求
    if event.get('source') == 'aws.events' and event.get('detail-type') == 'Scheduled Event':
        logger.info("收到Lambda预热请求")
        
        # 执行预热操作
        try:
            # 预加载客户端
            preload_clients()
            
            # 预热其他资源（如加载模型配置）
            from applications.backend.shared.config import Config
            Config.load()
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Lambda warmed up successfully',
                    'timestamp': int(time.time())
                })
            }
        except Exception as e:
            logger.error(f"预热失败: {e}")
            return {
                'statusCode': 500,
                'body': json.dumps({
                    'error': 'Warmup failed',
                    'message': str(e)
                })
            }
    
    # 不是预热请求，返回None让主处理器处理
    return None

# 智能重试装饰器
def smart_retry(max_attempts: int = 3, backoff_factor: float = 2.0):
    """
    智能重试装饰器
    针对特定错误类型进行指数退避重试
    """
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        def wrapper(*args, **kwargs):
            last_exception = None
            
            for attempt in range(max_attempts):
                try:
                    return func(*args, **kwargs)
                except Exception as e:
                    last_exception = e
                    
                    # 判断是否应该重试
                    if should_retry(e):
                        if attempt < max_attempts - 1:
                            wait_time = backoff_factor ** attempt
                            logger.warning(f"重试 {func.__name__} (尝试 {attempt + 1}/{max_attempts}), 等待 {wait_time}秒")
                            time.sleep(wait_time)
                        else:
                            logger.error(f"重试失败: {func.__name__} 已达最大尝试次数")
                    else:
                        # 不应重试的错误，直接抛出
                        raise
            
            # 所有重试都失败
            raise last_exception
        
        return wrapper
    return decorator

def should_retry(exception: Exception) -> bool:
    """判断错误是否应该重试"""
    # 可重试的错误类型
    retryable_errors = [
        'ThrottlingException',
        'RequestLimitExceeded',
        'ServiceUnavailable',
        'RequestTimeout',
        'InternalServerError'
    ]
    
    error_message = str(exception)
    return any(error in error_message for error in retryable_errors)

# 导出优化的查询处理器
class OptimizedQueryHandler(LambdaOptimizedHandler):
    """优化的查询处理器"""
    
    @performance_monitor(metric_name="query_processing_time")
    @smart_retry(max_attempts=3)
    def process_query(self, question: str, top_k: int = 5) -> Dict[str, Any]:
        """
        处理查询请求
        包含缓存、性能监控和重试机制
        """
        # 生成缓存键
        cache_key = f"query:{question}:{top_k}"
        
        # 检查缓存
        cached_response = self.get_cached_response(cache_key)
        if cached_response:
            logger.info("从缓存返回结果")
            return cached_response
        
        # 执行实际查询
        response = self._execute_query(question, top_k)
        
        # 缓存结果
        self.set_cached_response(cache_key, response)
        
        return response
    
    def _execute_query(self, question: str, top_k: int) -> Dict[str, Any]:
        """执行实际的查询逻辑"""
        # 这里是实际的查询实现
        knowledge_base_id = self._config_cache['knowledge_base_id']
        model_id = self._config_cache['model_id']
        
        response = self.bedrock_agent.retrieve_and_generate(
            input={'text': question},
            retrieveAndGenerateConfiguration={
                'type': 'KNOWLEDGE_BASE',
                'knowledgeBaseConfiguration': {
                    'knowledgeBaseId': knowledge_base_id,
                    'modelArn': f'arn:aws:bedrock:{self._config_cache["region"]}::foundation-model/{model_id}',
                    'retrievalConfiguration': {
                        'vectorSearchConfiguration': {
                            'numberOfResults': top_k
                        }
                    }
                }
            }
        )
        
        return response