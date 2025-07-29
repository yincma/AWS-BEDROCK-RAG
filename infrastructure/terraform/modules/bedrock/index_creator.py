import json
import os
import boto3
import requests
from requests_aws4auth import AWS4Auth
import time

def handler(event, context):
    """Create OpenSearch index for Bedrock Knowledge Base"""
    
    collection_endpoint = os.environ['COLLECTION_ENDPOINT']
    index_name = os.environ['INDEX_NAME']
    region = os.environ['REGION']
    
    # Get AWS credentials for signing
    credentials = boto3.Session().get_credentials()
    awsauth = AWS4Auth(
        credentials.access_key,
        credentials.secret_key,
        region,
        'aoss',
        session_token=credentials.token
    )
    
    # Create the index mapping
    index_body = {
        "settings": {
            "index": {
                "number_of_shards": 1,
                "number_of_replicas": 0,
                "knn": True,
                "knn.algo_param.ef_search": 512
            }
        },
        "mappings": {
            "properties": {
                "bedrock-knowledge-base-vector": {
                    "type": "knn_vector",
                    "dimension": 1536,
                    "method": {
                        "name": "hnsw",
                        "space_type": "l2",
                        "engine": "faiss",
                        "parameters": {
                            "ef_construction": 512,
                            "m": 16
                        }
                    }
                },
                "text": {
                    "type": "text"
                }
                # metadata字段不预定义，让Bedrock在首次索引时动态创建
                # 这避免了"object mapping tried to parse field as object, but found a concrete value"错误
            }
        }
    }
    
    # Wait for collection to be fully ready
    print(f"Waiting for collection to be ready...")
    time.sleep(30)
    
    url = f"{collection_endpoint}/{index_name}"
    headers = {"Content-Type": "application/json"}
    
    try:
        # First check if index exists
        print(f"Checking if index {index_name} exists...")
        check_response = requests.head(url, auth=awsauth)
        
        if check_response.status_code == 200:
            print(f"Index {index_name} already exists")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Index {index_name} already exists',
                    'status': 'exists'
                })
            }
        
        # Create index
        print(f"Creating index {index_name}...")
        response = requests.put(
            url,
            auth=awsauth,
            headers=headers,
            json=index_body
        )
        
        if response.status_code == 200:
            print(f"Successfully created index {index_name}")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Successfully created index {index_name}',
                    'status': 'created'
                })
            }
        else:
            print(f"Failed to create index: {response.status_code} - {response.text}")
            print(f"Response headers: {response.headers}")
            print(f"Request URL: {url}")
            return {
                'statusCode': response.status_code,
                'body': json.dumps({
                    'message': f'Failed to create index',
                    'error': response.text,
                    'headers': dict(response.headers),
                    'url': url
                })
            }
            
    except Exception as e:
        print(f"Error: {str(e)}")
        import traceback
        print(f"Traceback: {traceback.format_exc()}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Error creating index',
                'error': str(e),
                'traceback': traceback.format_exc()
            })
        }