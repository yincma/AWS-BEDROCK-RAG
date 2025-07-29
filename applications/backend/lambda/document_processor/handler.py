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
        """Create error response (fallback implementation)"""
        error_response = {
            "success": False,
            "error": {
                "code": status_code,
                "message": message
            },
            "timestamp": str(int(time.time()))
        }
        return create_success_response(error_response, status_code)

# Configure logging
logger = logging.getLogger()
log_level = config.features.log_level if config else os.getenv('LOG_LEVEL', 'INFO')
logger.setLevel(getattr(logging, log_level.upper(), logging.INFO))

# Get AWS configuration
if config:
    aws_config = {'region_name': config.region}
else:
    aws_config = {'region_name': os.environ.get('REGION', os.environ.get('AWS_REGION', 'us-east-1'))}

# AWS clients
s3_client = boto3.client('s3', **aws_config)
bedrock_agent = boto3.client('bedrock-agent', **aws_config)

@cors_handler
def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda function main handler
    
    Args:
        event: API Gateway event or S3 event
        context: Lambda context
        
    Returns:
        HTTP response
    """
    try:
        logger.info(f"Received event: {json.dumps(event, default=str)}")
        
        # Determine event type
        if 'httpMethod' in event:
            # API Gateway event - handle different requests based on HTTP method and path
            http_method = event.get('httpMethod', '')
            resource_path = event.get('resource', '')
            path_parameters = event.get('pathParameters', {})
            
            if resource_path == '/upload' and http_method == 'POST':
                return handle_upload_request(event)
            elif resource_path == '/documents' and http_method == 'GET':
                return handle_documents_list_request(event)
            elif resource_path == '/documents/{documentId}' and http_method == 'DELETE':
                return handle_delete_document(event)
            elif resource_path == '/documents/{documentId}' and http_method == 'GET':
                return handle_get_document(event)
            else:
                return create_error_response(400, f"Unsupported request: {http_method} {resource_path}")
        elif 'Records' in event and event['Records'][0].get('eventSource') == 'aws:s3':
            # S3 event - process document after upload
            return handle_s3_event(event)
        else:
            return create_error_response(400, "Unsupported event type")
    
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}", exc_info=True)
        return create_error_response(500, "Internal server error")

def handle_upload_request(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process document upload request and generate presigned URL
    
    Args:
        event: API Gateway event
        
    Returns:
        Response containing presigned URL
    """
    try:
        # Parse request body
        if 'body' in event and event['body']:
            body = json.loads(event['body'])
        else:
            return create_error_response(400, "Request body cannot be empty")
        
        # Extract file information
        filename = body.get('filename', '').strip()
        content_type = body.get('contentType', 'application/octet-stream')
        file_size = body.get('fileSize', 0)
        
        if not filename:
            return create_error_response(400, "Filename cannot be empty")
        
        # Validate file type
        if config:
            if not config.document.validate_file_extension(filename):
                allowed_extensions = config.document.allowed_file_extensions
                return create_error_response(400, f"Unsupported file type. Supported types: {', '.join(allowed_extensions)}")
        else:
            # Fallback validation (using environment variables)
            allowed_extensions = os.getenv('ALLOWED_FILE_EXTENSIONS', '.pdf,.txt,.docx,.doc,.md,.csv,.json').split(',')
            if not any(filename.lower().endswith(ext) for ext in allowed_extensions):
                return create_error_response(400, f"Unsupported file type. Supported types: {', '.join(allowed_extensions)}")
        
        # Validate file size
        if config:
            if not config.document.validate_file_size(file_size):
                max_size_mb = config.document.max_file_size_mb
                return create_error_response(400, f"File size exceeds limit ({max_size_mb}MB)")
        else:
            # Fallback validation (using environment variables)
            max_size_mb = int(os.getenv('MAX_FILE_SIZE_MB', '100'))
            max_size = max_size_mb * 1024 * 1024
            if file_size > max_size:
                return create_error_response(400, f"File size exceeds limit ({max_size_mb}MB)")
        
        # Generate unique filename
        file_id = str(uuid.uuid4())
        file_extension = filename[filename.rfind('.'):]
        
        # Generate S3 key
        if config:
            s3_key = config.get_s3_key(file_id, file_extension)
        else:
            document_prefix = os.getenv('DOCUMENT_PREFIX', 'documents/')
            s3_key = f"{document_prefix}{file_id}{file_extension}"
        
        # Get S3 bucket name
        bucket_name = config.s3.document_bucket if config else os.environ.get('S3_BUCKET')
        if not bucket_name:
            return create_error_response(500, "S3 bucket not configured")
        
        # Generate presigned URL
        # Get expiry time configuration
        expiry_seconds = config.document.presigned_url_expiry_seconds if config else int(os.getenv('PRESIGNED_URL_EXPIRY_SECONDS', '900'))
        
        # Note: Remove Metadata to simplify upload process and avoid encoding issues
        presigned_url = s3_client.generate_presigned_url(
            'put_object',
            Params={
                'Bucket': bucket_name,
                'Key': s3_key,
                'ContentType': content_type
            },
            ExpiresIn=expiry_seconds
        )
        
        # Add debug log
        logger.info(f"Generated presigned URL parameters: Bucket={bucket_name}, Key={s3_key}, ContentType={content_type}")
        
        # Build response - include success field and direct data
        result = {
            "success": True,
            "uploadUrl": presigned_url,
            "fileId": file_id,
            "s3Key": s3_key,
            "bucket": bucket_name,
            "expiresIn": expiry_seconds,
            "message": f"Presigned URL generated successfully, please complete upload within {expiry_seconds // 60} minutes"
        }
        
        logger.info(f"Successfully generated presigned URL for file {filename}: {s3_key}")
        
        # Return result directly to avoid double nesting
        return create_success_response(result)
    
    except Exception as e:
        logger.error(f"Failed to generate presigned URL: {str(e)}", exc_info=True)
        return create_error_response(500, f"Failed to generate upload URL: {str(e)}")

def handle_documents_list_request(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process get documents list request
    
    Args:
        event: API Gateway event
        
    Returns:
        Response containing documents list
    """
    try:
        # Log start of document list processing
        logger.info("Starting to process document list request")
        
        # Log configuration info (for debugging)
        if config:
            logger.info(f"Using config module: {config.get_config_summary()}")
        else:
            logger.info(f"Environment variables: S3_BUCKET={os.environ.get('S3_BUCKET')}, "
                        f"KNOWLEDGE_BASE_ID={os.environ.get('KNOWLEDGE_BASE_ID')}, "
                        f"DATA_SOURCE_ID={os.environ.get('DATA_SOURCE_ID')}")
        
        # Get S3 bucket name
        bucket_name = config.s3.document_bucket if config else os.environ.get('S3_BUCKET')
        if not bucket_name:
            logger.error("S3 bucket not configured")
            return create_error_response(500, "S3 bucket not configured")
        
        # Get document prefix
        document_prefix = config.s3.document_prefix if config else os.getenv('DOCUMENT_PREFIX', 'documents/')
        
        # List documents in S3 bucket
        response = s3_client.list_objects_v2(
            Bucket=bucket_name,
            Prefix=document_prefix
        )
        
        documents = []
        if 'Contents' in response:
            for obj in response['Contents']:
                # Skip folders
                if obj['Key'].endswith('/'):
                    continue
                    
                # Get file metadata
                try:
                    metadata_response = s3_client.head_object(
                        Bucket=bucket_name,
                        Key=obj['Key']
                    )
                    metadata = metadata_response.get('Metadata', {})
                    
                    # Extract file ID
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
                    logger.warning(f"Cannot get file metadata {obj['Key']}: {str(e)}")
                    continue
        
        # Build response
        result = {
            "success": True,
            "data": documents,
            "metadata": {
                "total": len(documents),
                "timestamp": str(int(time.time()))
            }
        }
        
        logger.info(f"Returning document list with {len(documents)} documents")
        return create_success_response(result)
    
    except Exception as e:
        logger.error(f"Failed to get document list: {str(e)}", exc_info=True)
        return create_error_response(500, f"Failed to get document list: {str(e)}")

def handle_s3_event(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process S3 upload event and trigger document processing workflow
    
    Args:
        event: S3 event
        
    Returns:
        Processing result
    """
    try:
        processed_files = []
        
        for record in event['Records']:
            bucket = record['s3']['bucket']['name']
            key = record['s3']['object']['key']
            
            logger.info(f"Processing S3 object: s3://{bucket}/{key}")
            
            # Trigger Knowledge Base data source sync
            result = trigger_knowledge_base_sync(key)
            
            processed_files.append({
                "bucket": bucket,
                "key": key,
                "syncResult": result
            })
        
        return create_success_response({
            "message": "Document processing completed",
            "processedFiles": processed_files
        })
    
    except Exception as e:
        logger.error(f"S3 event processing failed: {str(e)}", exc_info=True)
        return create_error_response(500, f"Document processing failed: {str(e)}")

def trigger_knowledge_base_sync(s3_key: str) -> Dict[str, Any]:
    """
    Trigger Knowledge Base data source sync
    
    Args:
        s3_key: S3 object key
        
    Returns:
        Sync result
    """
    try:
        # Get Knowledge Base configuration
        if config:
            knowledge_base_id = config.bedrock.knowledge_base_id
            data_source_id = config.bedrock.data_source_id
            bucket_name = config.s3.document_bucket
        else:
            knowledge_base_id = os.environ.get('KNOWLEDGE_BASE_ID')
            data_source_id = os.environ.get('DATA_SOURCE_ID')
            bucket_name = os.environ.get('S3_BUCKET')
        
        if not knowledge_base_id or not data_source_id:
            logger.warning("Knowledge Base ID or Data Source ID not configured, skipping sync")
            return {
                "status": "skipped",
                "reason": "Knowledge Base not configured"
            }
        
        # Verify file exists
        logger.info(f"Verifying file exists: s3://{bucket_name}/{s3_key}")
        try:
            s3_client.head_object(Bucket=bucket_name, Key=s3_key)
            logger.info(f"File confirmed exists: s3://{bucket_name}/{s3_key}")
        except Exception as e:
            logger.error(f"File does not exist or cannot be accessed: s3://{bucket_name}/{s3_key} - {str(e)}")
            return {
                "status": "failed",
                "error": f"File does not exist: {s3_key}",
                "bucket": bucket_name
            }
        
        # Start data source sync job
        logger.info(f"Starting Knowledge Base sync - KB: {knowledge_base_id}, DS: {data_source_id}")
        response = bedrock_agent.start_ingestion_job(
            knowledgeBaseId=knowledge_base_id,
            dataSourceId=data_source_id,
            description=f"Auto sync document: {s3_key}"
        )
        
        job_id = response.get('ingestionJob', {}).get('ingestionJobId')
        job_status = response.get('ingestionJob', {}).get('status')
        
        logger.info(f"Knowledge Base sync job started: {job_id}, initial status: {job_status}")
        
        # Check job status immediately (optional)
        try:
            status_response = bedrock_agent.get_ingestion_job(
                knowledgeBaseId=knowledge_base_id,
                dataSourceId=data_source_id,
                ingestionJobId=job_id
            )
            
            detailed_status = status_response.get('ingestionJob', {}).get('status')
            statistics = status_response.get('ingestionJob', {}).get('statistics', {})
            
            logger.info(f"Sync job detailed status: {detailed_status}, statistics: {statistics}")
            
            return {
                "status": "started",
                "jobId": job_id,
                "jobStatus": detailed_status,
                "knowledgeBaseId": knowledge_base_id,
                "dataSourceId": data_source_id,
                "statistics": statistics,
                "s3Key": s3_key,
                "bucket": bucket_name
            }
        except Exception as e:
            logger.warning(f"Cannot get sync job status: {str(e)}")
            return {
                "status": "started",
                "jobId": job_id,
                "knowledgeBaseId": knowledge_base_id,
                "dataSourceId": data_source_id,
                "s3Key": s3_key,
                "bucket": bucket_name
            }
    
    except Exception as e:
        logger.error(f"Failed to start Knowledge Base sync: {str(e)}", exc_info=True)
        return {
            "status": "failed",
            "error": str(e),
            "errorType": type(e).__name__,
            "knowledgeBaseId": knowledge_base_id if 'knowledge_base_id' in locals() else None,
            "dataSourceId": data_source_id if 'data_source_id' in locals() else None
        }

def handle_delete_document(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process delete document request
    
    Args:
        event: API Gateway event
        
    Returns:
        Delete result response
    """
    try:
        # Get document ID
        path_parameters = event.get('pathParameters', {})
        document_id = path_parameters.get('documentId')
        
        if not document_id:
            return create_error_response(400, "Document ID cannot be empty")
        
        logger.info(f"Starting to delete document: {document_id}")
        
        # Get S3 bucket name
        bucket_name = config.s3.document_bucket if config else os.environ.get('S3_BUCKET')
        if not bucket_name:
            return create_error_response(500, "S3 bucket not configured")
        
        # Get document prefix
        document_prefix = config.s3.document_prefix if config else os.getenv('DOCUMENT_PREFIX', 'documents/')
        
        # Find documents with specified ID
        # List all possible file extensions
        deleted_files = []
        errors = []
        
        # Try to list and delete all matching files
        try:
            response = s3_client.list_objects_v2(
                Bucket=bucket_name,
                Prefix=f"{document_prefix}{document_id}"
            )
            
            if 'Contents' in response:
                for obj in response['Contents']:
                    key = obj['Key']
                    # Ensure filename matches pattern: documents/{document_id}.{extension}
                    if key.startswith(f"{document_prefix}{document_id}."):
                        try:
                            s3_client.delete_object(Bucket=bucket_name, Key=key)
                            deleted_files.append(key)
                            logger.info(f"Successfully deleted file: s3://{bucket_name}/{key}")
                        except Exception as e:
                            logger.error(f"Failed to delete file {key}: {str(e)}")
                            errors.append({"key": key, "error": str(e)})
            
            if not deleted_files and not errors:
                return create_error_response(404, f"Document not found: {document_id}")
            
        except Exception as e:
            logger.error(f"Error listing documents: {str(e)}")
            return create_error_response(500, f"Failed to delete document: {str(e)}")
        
        # Trigger Knowledge Base data source sync (if configured)
        sync_result = None
        if deleted_files:
            sync_result = trigger_knowledge_base_sync(deleted_files[0])
        
        # Build response
        result = {
            "success": True,
            "documentId": document_id,
            "deletedFiles": deleted_files,
            "errors": errors if errors else None,
            "syncResult": sync_result,
            "message": f"Document {document_id} deleted successfully" if deleted_files else "No files found to delete"
        }
        
        logger.info(f"Document deletion completed: {document_id}, deleted {len(deleted_files)} files")
        return create_success_response(result)
        
    except Exception as e:
        logger.error(f"Failed to delete document: {str(e)}", exc_info=True)
        return create_error_response(500, f"删除文档失败: {str(e)}")

def handle_get_document(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process get single document request
    
    Args:
        event: API Gateway event
        
    Returns:
        Document information response
    """
    try:
        # Get document ID
        path_parameters = event.get('pathParameters', {})
        document_id = path_parameters.get('documentId')
        
        if not document_id:
            return create_error_response(400, "Document ID cannot be empty")
        
        logger.info(f"Getting document information: {document_id}")
        
        # Get S3 bucket name
        bucket_name = config.s3.document_bucket if config else os.environ.get('S3_BUCKET')
        if not bucket_name:
            return create_error_response(500, "S3 bucket not configured")
        
        # Get document prefix
        document_prefix = config.s3.document_prefix if config else os.getenv('DOCUMENT_PREFIX', 'documents/')
        
        # Find document
        try:
            response = s3_client.list_objects_v2(
                Bucket=bucket_name,
                Prefix=f"{document_prefix}{document_id}"
            )
            
            if 'Contents' not in response or not response['Contents']:
                return create_error_response(404, f"Document not found: {document_id}")
            
            # Get the first matching file
            for obj in response['Contents']:
                key = obj['Key']
                if key.startswith(f"{document_prefix}{document_id}."):
                    # Get file metadata
                    metadata_response = s3_client.head_object(
                        Bucket=bucket_name,
                        Key=key
                    )
                    metadata = metadata_response.get('Metadata', {})
                    
                    # Build document information
                    document = {
                        "id": document_id,
                        "name": metadata.get('original-filename', key.split('/')[-1]),
                        "size": obj['Size'],
                        "type": metadata.get('content-type', 'application/octet-stream'),
                        "upload_date": obj['LastModified'].isoformat(),
                        "s3_key": key,
                        "metadata": metadata
                    }
                    
                    result = {
                        "success": True,
                        "data": document
                    }
                    
                    logger.info(f"Successfully retrieved document information: {document_id}")
                    return create_success_response(result)
            
            return create_error_response(404, f"文档未找到: {document_id}")
            
        except Exception as e:
            logger.error(f"Error getting document information: {str(e)}")
            return create_error_response(500, f"Failed to get document: {str(e)}")
        
    except Exception as e:
        logger.error(f"Failed to get document: {str(e)}", exc_info=True)
        return create_error_response(500, f"获取文档失败: {str(e)}")

# These functions have already been defined as fallback implementations at the beginning of the file
