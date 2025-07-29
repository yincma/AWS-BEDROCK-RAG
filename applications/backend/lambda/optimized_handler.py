"""
Optimized Lambda handler base class
Implements cold start optimization, connection pool reuse, caching and other performance optimization measures
"""
import json
import logging
import os
import time
from functools import lru_cache, wraps
from typing import Dict, Any, Optional, Callable
import boto3
from botocore.config import Config

# Configure logging (initialize outside Lambda container)
logger = logging.getLogger()
logger.setLevel(os.getenv('LOG_LEVEL', 'INFO'))

# Global client cache (reduce cold start time)
_clients_cache = {}

# AWS client configuration
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
    Get or create AWS client (singleton pattern)
    Use connection pool to reuse connections and reduce latency
    """
    cache_key = f"{service_name}:{json.dumps(kwargs, sort_keys=True)}"
    
    if cache_key not in _clients_cache:
        client_kwargs = {'config': AWS_CONFIG}
        client_kwargs.update(kwargs)
        _clients_cache[cache_key] = boto3.client(service_name, **client_kwargs)
        logger.info(f"Creating new AWS client: {service_name}")
    
    return _clients_cache[cache_key]

# Preload common clients (execute when Lambda container starts)
def preload_clients():
    """Preload common AWS clients to reduce first request latency"""
    services = ['bedrock-runtime', 'bedrock-agent-runtime', 's3', 'cloudwatch']
    for service in services:
        try:
            get_aws_client(service)
        except Exception as e:
            logger.warning(f"Failed to preload client {service}: {e}")

# Execute when Lambda container starts
preload_clients()

class LambdaOptimizedHandler:
    """Optimized Lambda handler base class"""
    
    def __init__(self):
        # Get required clients during initialization
        self.bedrock_runtime = get_aws_client('bedrock-runtime')
        self.bedrock_agent = get_aws_client('bedrock-agent-runtime')
        self.s3 = get_aws_client('s3')
        self.cloudwatch = get_aws_client('cloudwatch')
        
        # Configure cache
        self._config_cache = {}
        self._load_config()
    
    def _load_config(self):
        """Load and cache configuration"""
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
        Memory cache response (suitable for frequent queries)
        Note: Lambda memory is limited, use with caution
        """
        # This is a placeholder, actual implementation needs to consider cache invalidation strategy
        return None
    
    def set_cached_response(self, cache_key: str, response: Dict[str, Any], ttl: int = 300):
        """Set cache response"""
        # In actual implementation, you can use ElastiCache or DynamoDB for distributed caching
        pass

def performance_monitor(metric_name: str = None):
    """
    Performance monitoring decorator
    Automatically records function execution time and sends CloudWatch metrics
    """
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        def wrapper(*args, **kwargs):
            start_time = time.time()
            
            try:
                result = func(*args, **kwargs)
                execution_time = (time.time() - start_time) * 1000  # Convert to milliseconds
                
                # Send performance metrics
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
                    logger.warning(f"Failed to send performance metrics: {e}")
                
                # Log slow queries
                if execution_time > 3000:  # 3 seconds
                    logger.warning(f"Slow query detected: {func.__name__} took {execution_time:.2f}ms")
                
                return result
                
            except Exception as e:
                execution_time = (time.time() - start_time) * 1000
                logger.error(f"Function execution failed: {func.__name__}, took {execution_time:.2f}ms", exc_info=True)
                raise
        
        return wrapper
    return decorator

def batch_processor(batch_size: int = 25):
    """
    Batch processing decorator
    Merge multiple requests for processing to improve throughput
    """
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        def wrapper(items: list, *args, **kwargs):
            results = []
            
            # Process in batches
            for i in range(0, len(items), batch_size):
                batch = items[i:i + batch_size]
                try:
                    batch_results = func(batch, *args, **kwargs)
                    results.extend(batch_results)
                except Exception as e:
                    logger.error(f"Batch processing failed (batch {i//batch_size + 1}): {e}")
                    # Continue processing other batches
                    results.extend([None] * len(batch))
            
            return results
        
        return wrapper
    return decorator

class ConnectionPool:
    """
    Connection pool manager
    Used to manage external service connections (e.g., OpenSearch)
    """
    def __init__(self, max_connections: int = 10):
        self.max_connections = max_connections
        self._connections = []
        self._available = []
    
    def get_connection(self):
        """Get available connection"""
        if self._available:
            return self._available.pop()
        elif len(self._connections) < self.max_connections:
            conn = self._create_connection()
            self._connections.append(conn)
            return conn
        else:
            # Wait for available connection
            raise RuntimeError("Connection pool is full")
    
    def release_connection(self, conn):
        """Release connection back to pool"""
        if conn in self._connections:
            self._available.append(conn)
    
    def _create_connection(self):
        """Create new connection (subclass implementation)"""
        raise NotImplementedError

# Warmup handler
def warmup_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda warmup handler
    Handle CloudWatch Events warmup requests
    """
    # Check if it's a warmup request
    if event.get('source') == 'aws.events' and event.get('detail-type') == 'Scheduled Event':
        logger.info("Received Lambda warmup request")
        
        # Execute warmup operations
        try:
            # Preload clients
            preload_clients()
            
            # Warm up other resources (e.g., load model configuration)
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
            logger.error(f"Warmup failed: {e}")
            return {
                'statusCode': 500,
                'body': json.dumps({
                    'error': 'Warmup failed',
                    'message': str(e)
                })
            }
    
    # Not a warmup request, return None to let main handler process
    return None

# Smart retry decorator
def smart_retry(max_attempts: int = 3, backoff_factor: float = 2.0):
    """
    Smart retry decorator
    Exponential backoff retry for specific error types
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
                    
                    # Determine if should retry
                    if should_retry(e):
                        if attempt < max_attempts - 1:
                            wait_time = backoff_factor ** attempt
                            logger.warning(f"Retrying {func.__name__} (attempt {attempt + 1}/{max_attempts}), waiting {wait_time} seconds")
                            time.sleep(wait_time)
                        else:
                            logger.error(f"Retry failed: {func.__name__} reached maximum attempts")
                    else:
                        # Non-retryable error, raise directly
                        raise
            
            # All retries failed
            raise last_exception
        
        return wrapper
    return decorator

def should_retry(exception: Exception) -> bool:
    """Determine if error should be retried"""
    # Retryable error types
    retryable_errors = [
        'ThrottlingException',
        'RequestLimitExceeded',
        'ServiceUnavailable',
        'RequestTimeout',
        'InternalServerError'
    ]
    
    error_message = str(exception)
    return any(error in error_message for error in retryable_errors)

# Export optimized query handler
class OptimizedQueryHandler(LambdaOptimizedHandler):
    """Optimized query handler"""
    
    @performance_monitor(metric_name="query_processing_time")
    @smart_retry(max_attempts=3)
    def process_query(self, question: str, top_k: int = 5) -> Dict[str, Any]:
        """
        Process query request
        Includes caching, performance monitoring and retry mechanism
        """
        # Generate cache key
        cache_key = f"query:{question}:{top_k}"
        
        # Check cache
        cached_response = self.get_cached_response(cache_key)
        if cached_response:
            logger.info("Returning result from cache")
            return cached_response
        
        # Execute actual query
        response = self._execute_query(question, top_k)
        
        # Cache result
        self.set_cached_response(cache_key, response)
        
        return response
    
    def _execute_query(self, question: str, top_k: int) -> Dict[str, Any]:
        """Execute actual query logic"""
        # This is the actual query implementation
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