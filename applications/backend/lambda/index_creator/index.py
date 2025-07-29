import json
import boto3
import time
from opensearchpy import OpenSearch, RequestsHttpConnection, AWSV4SignerAuth
from opensearchpy.exceptions import ConnectionError, AuthorizationException
import urllib3
from typing import Dict, Any

# 导入共享的CORS工具函数
try:
    from shared.utils.cors import create_error_response, create_success_response
except ImportError:
    # 如果导入失败，定义简单的回退函数
    def create_error_response(status_code: int, error_message: str, cors_enabled: bool = True) -> Dict[str, Any]:
        response = {
            "statusCode": status_code,
            "body": json.dumps({"error": error_message}, ensure_ascii=False)
        }
        if cors_enabled:
            response["headers"] = {
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
                "Access-Control-Allow-Headers": "Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token"
            }
        return response
    
    def create_success_response(data: Any, cors_enabled: bool = True) -> Dict[str, Any]:
        response = {
            "statusCode": 200,
            "body": json.dumps(data, ensure_ascii=False)
        }
        if cors_enabled:
            response["headers"] = {
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
                "Access-Control-Allow-Headers": "Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token"
            }
        return response

# Disable SSL warnings for development (remove in production)
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

def retry_with_backoff(func, max_retries=3, initial_delay=1, backoff_factor=2):
    """
    执行函数并在失败时进行指数退避重试
    """
    for attempt in range(max_retries):
        try:
            return func()
        except Exception as e:
            if attempt == max_retries - 1:
                raise
            
            delay = initial_delay * (backoff_factor ** attempt)
            print(f"Attempt {attempt + 1} failed: {str(e)}")
            print(f"Retrying in {delay} seconds...")
            time.sleep(delay)

def wait_for_collection_ready(client, max_wait=60):
    """
    等待 OpenSearch 集合就绪
    """
    start_time = time.time()
    while time.time() - start_time < max_wait:
        try:
            info = client.info()
            print(f"Collection is ready: {json.dumps(info, default=str)}")
            return True
        except Exception as e:
            print(f"Collection not ready yet: {str(e)}")
            time.sleep(5)
    
    return False

def create_index_with_retry(client, index_name: str, index_body: Dict[str, Any], max_retries: int = 3) -> Dict[str, Any]:
    """
    创建索引并进行重试
    """
    def create_index():
        return client.indices.create(
            index=index_name,
            body=index_body
        )
    
    return retry_with_backoff(create_index, max_retries=max_retries)

def lambda_handler(event, context):
    """
    Lambda function to create OpenSearch index for Bedrock Knowledge Base
    支持重试和更好的错误处理
    """
    print("Starting index creation process with enhanced retry logic...")
    print(f"Event: {json.dumps(event)}")
    
    # Get parameters from event
    collection_endpoint = event['collection_endpoint']
    index_name = event.get('index_name', 'bedrock-knowledge-base-default-index')
    region = event.get('region', 'us-east-1')
    max_retries = event.get('max_retries', 3)
    wait_for_ready = event.get('wait_for_ready', True)
    force_recreate = event.get('force_recreate', False)  # 新增参数：强制重新创建
    
    # Clean up endpoint URL
    if collection_endpoint.startswith('https://'):
        host = collection_endpoint.replace('https://', '').rstrip('/')
    else:
        host = collection_endpoint.rstrip('/')
    
    print(f"Using host: {host}")
    print(f"Region: {region}")
    print(f"Index name: {index_name}")
    print(f"Max retries: {max_retries}")
    
    try:
        # Get credentials using boto3
        credentials = boto3.Session().get_credentials()
        
        # Create auth using AWSV4SignerAuth (newer method for OpenSearch)
        auth = AWSV4SignerAuth(credentials, region, 'aoss')
        
        # Create OpenSearch client with retry configuration
        client = OpenSearch(
            hosts=[{'host': host, 'port': 443}],
            http_auth=auth,
            use_ssl=True,
            verify_certs=True,
            connection_class=RequestsHttpConnection,
            timeout=60,  # 增加超时时间
            retry_on_timeout=True,
            max_retries=3
        )
        
        print("OpenSearch client created successfully")
        
        # Wait for collection to be ready if requested
        if wait_for_ready:
            print("Waiting for collection to be ready...")
            if not wait_for_collection_ready(client, max_wait=120):
                print("Warning: Collection may not be fully ready")
        
        # Check if index already exists
        def check_index_exists():
            return client.indices.exists(index=index_name)
        
        try:
            exists = retry_with_backoff(check_index_exists, max_retries=2, initial_delay=2)
            if exists:
                print(f"Index '{index_name}' already exists")
                if force_recreate:
                    print(f"Force recreate is enabled, deleting existing index...")
                    try:
                        # 删除现有索引
                        def delete_index():
                            return client.indices.delete(index=index_name)
                        
                        retry_with_backoff(delete_index, max_retries=3, initial_delay=2)
                        print(f"Successfully deleted existing index '{index_name}'")
                        
                        # 等待索引删除完成
                        print("Waiting for index deletion to complete...")
                        time.sleep(10)
                    except Exception as del_e:
                        print(f"Error deleting index: {str(del_e)}")
                        # 继续尝试创建
                else:
                    return create_success_response({
                        'message': 'Index already exists',
                        'index_name': index_name,
                        'status': 'success'
                    })
        except Exception as e:
            print(f"Error checking index existence: {str(e)}")
            print("Assuming index does not exist, proceeding with creation...")
        
        # Index configuration for Bedrock Knowledge Base
        # 使用更兼容的配置
        index_body = {
            "settings": {
                "index": {
                    "knn": True,
                    "knn.algo_param.ef_search": 512
                }
            },
            "mappings": {
                "properties": {
                    "bedrock-knowledge-base-vector": {
                        "type": "knn_vector",
                        "dimension": 1536,  # For Titan Embeddings G1
                        "method": {
                            "engine": "faiss",  # 使用 faiss 以兼容 Bedrock
                            "space_type": "l2",  # FAISS 默认使用 L2 距离
                            "name": "hnsw",
                            "parameters": {
                                "ef_construction": 512,
                                "m": 16,
                                "ef_search": 512
                            }
                        }
                    },
                    "text": {
                        "type": "text"
                    },
                    "metadata": {
                        "type": "object",
                        "enabled": false  # 禁用对象解析，存储原始值
                    }
                }
            }
        }
        
        print(f"Creating index with configuration: {json.dumps(index_body)}")
        
        # Create the index with retry
        try:
            response = create_index_with_retry(client, index_name, index_body, max_retries)
            print(f"Successfully created index '{index_name}'")
            print(f"Response: {json.dumps(response, default=str)}")
            
            # Wait for index to be ready
            print("Waiting for index to be ready...")
            time.sleep(10)
            
            # Verify index was created
            def verify_index():
                return client.indices.get(index=index_name)
            
            try:
                index_info = retry_with_backoff(verify_index, max_retries=3, initial_delay=2)
                print(f"Verified: Index '{index_name}' exists with info: {json.dumps(index_info, default=str)}")
            except Exception as e:
                print(f"Could not verify index existence: {str(e)}")
                # This is not critical, continue
            
            return create_success_response({
                'message': 'Index created successfully',
                'index_name': index_name,
                'status': 'success',
                'response': response
            })
            
        except AuthorizationException as e:
            error_message = str(e)
            print(f"Authorization error creating index: {error_message}")
            print("Please check:")
            print("1. The Lambda execution role has the correct policies attached")
            print("2. The OpenSearch data access policy includes the Lambda role")
            print("3. The OpenSearch collection is active and accessible")
            
            return create_error_response(403, error_message)
            
        except ConnectionError as e:
            error_message = str(e)
            print(f"Connection error: {error_message}")
            print("The OpenSearch collection may not be ready yet")
            
            return create_error_response(503, error_message)
            
        except Exception as e:
            error_message = str(e)
            print(f"Error creating index: {error_message}")
            
            return create_error_response(500, error_message)
    
    except Exception as e:
        error_message = str(e)
        print(f"Unexpected error: {error_message}")
        import traceback
        print(f"Traceback: {traceback.format_exc()}")
        
        return create_error_response(500, error_message)