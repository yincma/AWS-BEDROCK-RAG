import json
import boto3
import time
from opensearchpy import OpenSearch, RequestsHttpConnection
from requests_aws4auth import AWS4Auth

def create_index(host, index_name, aws_auth):
    """Create OpenSearch index with proper mappings for Bedrock Knowledge Base"""
    
    client = OpenSearch(
        hosts=[{'host': host, 'port': 443}],
        http_auth=aws_auth,
        use_ssl=True,
        verify_certs=True,
        connection_class=RequestsHttpConnection
    )
    
    # Index configuration for Bedrock Knowledge Base
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
                    "dimension": 1536,  # Amazon Titan Embeddings dimension
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
                },
                "metadata": {
                    "type": "object",
                    "dynamic": true,
                    "properties": {
                        "source": {
                            "type": "keyword"
                        },
                        "document_id": {
                            "type": "keyword"
                        }
                    }
                }
            }
        }
    }
    
    try:
        # Check if index exists
        if not client.indices.exists(index=index_name):
            response = client.indices.create(index=index_name, body=index_body)
            print(f"Index {index_name} created successfully: {response}")
            return True
        else:
            print(f"Index {index_name} already exists")
            return True
    except Exception as e:
        print(f"Error creating index: {str(e)}")
        return False

def handler(event, context):
    """Lambda handler to initialize OpenSearch index"""
    
    collection_endpoint = event['CollectionEndpoint']
    index_name = event.get('IndexName', 'bedrock-knowledge-base-index')
    region = event.get('Region', 'us-east-1')
    
    # Get AWS credentials
    credentials = boto3.Session().get_credentials()
    aws_auth = AWS4Auth(
        credentials.access_key,
        credentials.secret_key,
        region,
        'aoss',
        session_token=credentials.token
    )
    
    # Extract host from endpoint
    host = collection_endpoint.replace('https://', '').replace('/', '')
    
    # Wait for collection to be ready
    time.sleep(30)
    
    # Create index
    success = create_index(host, index_name, aws_auth)
    
    return {
        'statusCode': 200 if success else 500,
        'body': json.dumps({
            'success': success,
            'index_name': index_name,
            'collection_endpoint': collection_endpoint
        })
    }