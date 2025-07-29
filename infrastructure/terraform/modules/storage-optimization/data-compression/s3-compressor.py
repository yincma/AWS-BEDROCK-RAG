"""
S3 Automatic Compression Lambda Function

Compresses files in S3 to reduce storage costs.
Supports multiple compression algorithms and parallel processing.
"""

import os
import json
import boto3
import gzip
import brotli
import zlib
import concurrent.futures
from typing import Dict, List, Optional, Tuple
import mimetypes
import tempfile
import shutil

s3_client = boto3.client('s3')

# Configuration from environment variables
COMPRESSION_TYPES = json.loads(os.environ.get('COMPRESSION_TYPES', '["gzip"]'))
MIN_FILE_SIZE_BYTES = int(os.environ.get('MIN_FILE_SIZE_BYTES', '1024'))
SKIP_COMPRESSED = os.environ.get('SKIP_COMPRESSED', 'true').lower() == 'true'
PARALLEL_PROCESSING = os.environ.get('PARALLEL_PROCESSING', 'true').lower() == 'true'
MAX_WORKERS = int(os.environ.get('MAX_WORKERS', '10'))

# Compression file extensions
COMPRESSED_EXTENSIONS = {'.gz', '.br', '.zip', '.bz2', '.xz', '.7z', '.rar'}


def handler(event, context):
    """
    Main Lambda handler for S3 compression.
    """
    print(f"Processing event: {json.dumps(event)}")
    
    # Handle S3 event notification
    if 'Records' in event:
        results = []
        for record in event['Records']:
            if record['eventName'].startswith('s3:ObjectCreated:'):
                bucket = record['s3']['bucket']['name']
                key = record['s3']['object']['key']
                size = record['s3']['object'].get('size', 0)
                
                result = process_file(bucket, key, size)
                results.append(result)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'processed': len(results),
                'results': results
            })
        }
    
    # Handle scheduled batch processing
    elif 'batch_mode' in event:
        bucket_name = event['bucket_name']
        file_extensions = event.get('file_extensions', ['.json', '.log', '.txt', '.csv'])
        
        results = batch_compress_bucket(bucket_name, file_extensions)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'bucket': bucket_name,
                'processed': len(results),
                'results': results
            })
        }
    
    else:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'Invalid event format'})
        }


def process_file(bucket: str, key: str, size: int) -> Dict:
    """
    Process a single file for compression.
    """
    # Skip if file is too small
    if size < MIN_FILE_SIZE_BYTES:
        return {
            'bucket': bucket,
            'key': key,
            'status': 'skipped',
            'reason': f'File size ({size}) below minimum ({MIN_FILE_SIZE_BYTES})'
        }
    
    # Skip if already compressed
    if SKIP_COMPRESSED and is_compressed(key):
        return {
            'bucket': bucket,
            'key': key,
            'status': 'skipped',
            'reason': 'Already compressed'
        }
    
    # Download file
    with tempfile.NamedTemporaryFile(delete=False) as tmp_file:
        try:
            s3_client.download_fileobj(
                Bucket=bucket,
                Key=key,
                Fileobj=tmp_file
            )
            tmp_file.flush()
            original_path = tmp_file.name
            
            # Get file metadata
            response = s3_client.head_object(Bucket=bucket, Key=key)
            content_type = response.get('ContentType', 'application/octet-stream')
            metadata = response.get('Metadata', {})
            
            # Compress file
            best_compression = find_best_compression(original_path, COMPRESSION_TYPES)
            
            if best_compression['ratio'] < 0.9:  # Only compress if we save >10%
                compressed_path = best_compression['path']
                compressed_key = f"{key}.{best_compression['type']}"
                
                # Upload compressed file
                with open(compressed_path, 'rb') as compressed_file:
                    s3_client.upload_fileobj(
                        compressed_file,
                        bucket,
                        compressed_key,
                        ExtraArgs={
                            'ContentType': content_type,
                            'ContentEncoding': best_compression['type'],
                            'Metadata': {
                                **metadata,
                                'original-size': str(size),
                                'compressed-size': str(best_compression['size']),
                                'compression-ratio': f"{best_compression['ratio']:.2f}",
                                'compression-type': best_compression['type']
                            },
                            'StorageClass': 'STANDARD_IA'  # Move to IA immediately
                        }
                    )
                
                # Delete original file (optional - can be configured)
                # s3_client.delete_object(Bucket=bucket, Key=key)
                
                # Tag original as compressed
                s3_client.put_object_tagging(
                    Bucket=bucket,
                    Key=key,
                    Tagging={
                        'TagSet': [
                            {'Key': 'compressed', 'Value': 'true'},
                            {'Key': 'compressed-version', 'Value': compressed_key}
                        ]
                    }
                )
                
                # Log metrics
                print(f"Compression complete - Original: {size}, "
                      f"Compressed: {best_compression['size']}, "
                      f"Ratio: {best_compression['ratio']:.2f}")
                
                return {
                    'bucket': bucket,
                    'key': key,
                    'status': 'compressed',
                    'original_size': size,
                    'compressed_size': best_compression['size'],
                    'compression_ratio': best_compression['ratio'],
                    'compression_type': best_compression['type'],
                    'compressed_key': compressed_key,
                    'savings_bytes': size - best_compression['size']
                }
            else:
                return {
                    'bucket': bucket,
                    'key': key,
                    'status': 'skipped',
                    'reason': f'Compression ratio too low ({best_compression["ratio"]:.2f})'
                }
                
        except Exception as e:
            print(f"Error processing file {bucket}/{key}: {e}")
            return {
                'bucket': bucket,
                'key': key,
                'status': 'error',
                'error': str(e)
            }
        finally:
            # Cleanup temp files
            cleanup_temp_files(original_path)
            if 'best_compression' in locals():
                cleanup_temp_files(best_compression.get('path'))


def is_compressed(key: str) -> bool:
    """
    Check if file is already compressed based on extension.
    """
    _, ext = os.path.splitext(key.lower())
    return ext in COMPRESSED_EXTENSIONS


def find_best_compression(file_path: str, compression_types: List[str]) -> Dict:
    """
    Try different compression algorithms and find the best one.
    """
    original_size = os.path.getsize(file_path)
    best_result = {
        'type': 'none',
        'size': original_size,
        'ratio': 1.0,
        'path': file_path
    }
    
    if PARALLEL_PROCESSING and len(compression_types) > 1:
        # Parallel compression testing
        with concurrent.futures.ThreadPoolExecutor(max_workers=min(len(compression_types), MAX_WORKERS)) as executor:
            future_to_type = {
                executor.submit(compress_file, file_path, comp_type): comp_type
                for comp_type in compression_types
            }
            
            for future in concurrent.futures.as_completed(future_to_type):
                result = future.result()
                if result and result['ratio'] < best_result['ratio']:
                    # Clean up previous best
                    if best_result['path'] != file_path:
                        cleanup_temp_files(best_result['path'])
                    best_result = result
    else:
        # Sequential compression testing
        for comp_type in compression_types:
            result = compress_file(file_path, comp_type)
            if result and result['ratio'] < best_result['ratio']:
                # Clean up previous best
                if best_result['path'] != file_path:
                    cleanup_temp_files(best_result['path'])
                best_result = result
    
    return best_result


def compress_file(file_path: str, compression_type: str) -> Optional[Dict]:
    """
    Compress file using specified algorithm.
    """
    try:
        if compression_type == 'gzip':
            compressed_path = f"{file_path}.gz"
            with open(file_path, 'rb') as f_in:
                with gzip.open(compressed_path, 'wb', compresslevel=9) as f_out:
                    shutil.copyfileobj(f_in, f_out)
        
        elif compression_type == 'brotli':
            compressed_path = f"{file_path}.br"
            with open(file_path, 'rb') as f_in:
                with open(compressed_path, 'wb') as f_out:
                    f_out.write(brotli.compress(f_in.read(), quality=11))
        
        elif compression_type == 'zlib':
            compressed_path = f"{file_path}.z"
            with open(file_path, 'rb') as f_in:
                with open(compressed_path, 'wb') as f_out:
                    f_out.write(zlib.compress(f_in.read(), level=9))
        
        else:
            return None
        
        compressed_size = os.path.getsize(compressed_path)
        original_size = os.path.getsize(file_path)
        
        return {
            'type': compression_type,
            'size': compressed_size,
            'ratio': compressed_size / original_size,
            'path': compressed_path
        }
        
    except Exception as e:
        print(f"Error compressing with {compression_type}: {e}")
        return None


def batch_compress_bucket(bucket_name: str, file_extensions: List[str]) -> List[Dict]:
    """
    Batch compress files in a bucket.
    """
    results = []
    
    paginator = s3_client.get_paginator('list_objects_v2')
    
    for page in paginator.paginate(Bucket=bucket_name):
        if 'Contents' not in page:
            continue
        
        # Filter files by extension
        files_to_process = []
        for obj in page['Contents']:
            key = obj['Key']
            size = obj['Size']
            
            # Check file extension
            _, ext = os.path.splitext(key.lower())
            if ext in file_extensions and size >= MIN_FILE_SIZE_BYTES:
                # Check if already processed
                try:
                    tags_response = s3_client.get_object_tagging(
                        Bucket=bucket_name,
                        Key=key
                    )
                    tags = {tag['Key']: tag['Value'] for tag in tags_response['TagSet']}
                    if tags.get('compressed') != 'true':
                        files_to_process.append((key, size))
                except:
                    files_to_process.append((key, size))
        
        # Process files in parallel
        if PARALLEL_PROCESSING:
            with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
                future_to_file = {
                    executor.submit(process_file, bucket_name, key, size): (key, size)
                    for key, size in files_to_process
                }
                
                for future in concurrent.futures.as_completed(future_to_file):
                    result = future.result()
                    results.append(result)
        else:
            for key, size in files_to_process:
                result = process_file(bucket_name, key, size)
                results.append(result)
    
    # Log summary
    total_saved = sum(r.get('savings_bytes', 0) for r in results if r['status'] == 'compressed')
    print(f"Batch compression complete. Total savings: {total_saved / (1024**3):.2f} GB")
    
    return results


def cleanup_temp_files(*file_paths):
    """
    Clean up temporary files.
    """
    for file_path in file_paths:
        if file_path and os.path.exists(file_path):
            try:
                os.unlink(file_path)
            except Exception as e:
                print(f"Error cleaning up {file_path}: {e}")