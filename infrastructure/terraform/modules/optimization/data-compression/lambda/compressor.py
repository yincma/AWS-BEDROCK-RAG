#!/usr/bin/env python3
"""
Data Compressor Lambda Function
实现多种压缩算法，优化存储成本
"""

import json
import boto3
import os
import gzip
import bz2
import lzma
import tempfile
from typing import Dict, Tuple, Optional
import mimetypes
import base64
from datetime import datetime

# 初始化AWS客户端
s3_client = boto3.client('s3')
cloudwatch_client = boto3.client('cloudwatch')

# 环境变量
COMPRESSION_SETTINGS = json.loads(os.environ.get('COMPRESSION_SETTINGS', '{}'))
TARGET_BUCKET = os.environ.get('TARGET_BUCKET')
ENABLE_ENCRYPTION = os.environ.get('ENABLE_ENCRYPTION', 'true').lower() == 'true'
KMS_KEY_ID = os.environ.get('KMS_KEY_ID', '')

# 压缩算法映射
COMPRESSION_ALGORITHMS = {
    'gzip': {
        'extension': '.gz',
        'content_encoding': 'gzip',
        'compress_func': lambda data, level: gzip.compress(data, compresslevel=level)
    },
    'bzip2': {
        'extension': '.bz2',
        'content_encoding': 'bzip2',
        'compress_func': lambda data, level: bz2.compress(data, compresslevel=level)
    },
    'xz': {
        'extension': '.xz',
        'content_encoding': 'xz',
        'compress_func': lambda data, level: lzma.compress(data, preset=level)
    },
    'zstd': {
        'extension': '.zst',
        'content_encoding': 'zstd',
        'compress_func': None  # 需要外部库
    },
    'lz4': {
        'extension': '.lz4',
        'content_encoding': 'lz4',
        'compress_func': None  # 需要外部库
    }
}

def handler(event, context):
    """
    Lambda处理函数
    """
    # 处理S3事件或直接调用
    if 'Records' in event:
        # S3事件触发
        for record in event['Records']:
            bucket = record['s3']['bucket']['name']
            key = record['s3']['object']['key']
            size = record['s3']['object']['size']
            
            result = process_file(bucket, key, size)
            if result:
                publish_metrics(result)
    else:
        # 直接调用
        bucket = event.get('bucket')
        key = event.get('key')
        compression_type = event.get('compressionType')
        
        if not bucket or not key:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Missing bucket or key'})
            }
        
        # 获取文件大小
        head_response = s3_client.head_object(Bucket=bucket, Key=key)
        size = head_response['ContentLength']
        
        result = process_file(bucket, key, size, compression_type)
        if result:
            publish_metrics(result)
            return {
                'statusCode': 200,
                'body': json.dumps(result)
            }
        else:
            return {
                'statusCode': 500,
                'body': json.dumps({'error': 'Compression failed'})
            }

def process_file(bucket: str, key: str, size: int, 
                compression_type: Optional[str] = None) -> Optional[Dict]:
    """
    处理单个文件的压缩
    """
    print(f"Processing file: s3://{bucket}/{key} (size: {size} bytes)")
    
    # 检查文件是否已经压缩
    if is_compressed(key):
        print(f"File {key} is already compressed, skipping")
        return None
    
    # 确定压缩算法
    if not compression_type:
        compression_type = determine_compression_type(key, size)
    
    if not compression_type:
        print(f"No suitable compression for {key}")
        return None
    
    # 下载文件
    with tempfile.NamedTemporaryFile() as tmp_input:
        s3_client.download_file(bucket, key, tmp_input.name)
        
        # 读取文件内容
        with open(tmp_input.name, 'rb') as f:
            original_data = f.read()
        
        # 压缩文件
        compressed_data, compression_ratio = compress_data(
            original_data, 
            compression_type,
            get_compression_level(compression_type, key)
        )
        
        if not compressed_data:
            print(f"Failed to compress {key}")
            return None
        
        # 检查压缩效果
        if compression_ratio > 0.9:  # 压缩率低于10%
            print(f"Poor compression ratio ({compression_ratio:.2f}) for {key}, skipping")
            return None
        
        # 生成新的键名
        new_key = generate_compressed_key(key, compression_type)
        
        # 上传压缩文件
        upload_compressed_file(
            compressed_data, 
            new_key, 
            compression_type,
            original_metadata=get_object_metadata(bucket, key)
        )
        
        # 返回结果
        return {
            'original_key': key,
            'compressed_key': new_key,
            'original_size': size,
            'compressed_size': len(compressed_data),
            'compression_ratio': compression_ratio,
            'space_saved': size - len(compressed_data),
            'algorithm': compression_type,
            'timestamp': datetime.utcnow().isoformat()
        }

def is_compressed(key: str) -> bool:
    """
    检查文件是否已经压缩
    """
    compressed_extensions = ['.gz', '.bz2', '.xz', '.zst', '.lz4', '.zip', '.rar', '.7z']
    return any(key.lower().endswith(ext) for ext in compressed_extensions)

def determine_compression_type(key: str, size: int) -> Optional[str]:
    """
    根据文件类型和大小确定压缩算法
    """
    # 获取文件扩展名
    _, ext = os.path.splitext(key.lower())
    
    # 遍历压缩设置
    for category, settings in COMPRESSION_SETTINGS.items():
        if ext in settings.get('extensions', []):
            min_size_bytes = settings.get('min_size_mb', 1) * 1024 * 1024
            if size >= min_size_bytes:
                return settings.get('algorithm', 'gzip')
    
    # 默认压缩策略
    if size > 10 * 1024 * 1024:  # 大于10MB
        return 'gzip'
    
    return None

def get_compression_level(compression_type: str, key: str) -> int:
    """
    获取压缩级别
    """
    _, ext = os.path.splitext(key.lower())
    
    for category, settings in COMPRESSION_SETTINGS.items():
        if ext in settings.get('extensions', []):
            return settings.get('level', 6)
    
    # 默认压缩级别
    default_levels = {
        'gzip': 6,
        'bzip2': 9,
        'xz': 6,
        'zstd': 3,
        'lz4': 1
    }
    
    return default_levels.get(compression_type, 6)

def compress_data(data: bytes, algorithm: str, level: int) -> Tuple[Optional[bytes], float]:
    """
    压缩数据
    """
    try:
        if algorithm == 'gzip':
            compressed = gzip.compress(data, compresslevel=level)
        elif algorithm == 'bzip2':
            compressed = bz2.compress(data, compresslevel=level)
        elif algorithm == 'xz':
            compressed = lzma.compress(data, preset=level)
        elif algorithm == 'zstd':
            # 尝试使用zstandard库
            try:
                import zstandard as zstd
                cctx = zstd.ZstdCompressor(level=level)
                compressed = cctx.compress(data)
            except ImportError:
                print("zstandard library not available, falling back to gzip")
                compressed = gzip.compress(data, compresslevel=level)
                algorithm = 'gzip'
        elif algorithm == 'lz4':
            # 尝试使用lz4库
            try:
                import lz4.frame
                compressed = lz4.frame.compress(data, compression_level=level)
            except ImportError:
                print("lz4 library not available, falling back to gzip")
                compressed = gzip.compress(data, compresslevel=level)
                algorithm = 'gzip'
        else:
            print(f"Unknown compression algorithm: {algorithm}")
            return None, 0
        
        compression_ratio = len(compressed) / len(data) if len(data) > 0 else 0
        print(f"Compressed with {algorithm}: {len(data)} -> {len(compressed)} bytes (ratio: {compression_ratio:.2f})")
        
        return compressed, compression_ratio
        
    except Exception as e:
        print(f"Compression error: {e}")
        return None, 0

def generate_compressed_key(original_key: str, algorithm: str) -> str:
    """
    生成压缩文件的新键名
    """
    # 在原路径基础上添加compressed前缀
    parts = original_key.split('/')
    filename = parts[-1]
    path = '/'.join(parts[:-1])
    
    # 添加压缩扩展名
    extension = COMPRESSION_ALGORITHMS.get(algorithm, {}).get('extension', '.gz')
    
    if path:
        new_key = f"{path}/compressed/{filename}{extension}"
    else:
        new_key = f"compressed/{filename}{extension}"
    
    return new_key

def get_object_metadata(bucket: str, key: str) -> Dict:
    """
    获取对象元数据
    """
    try:
        response = s3_client.head_object(Bucket=bucket, Key=key)
        return response.get('Metadata', {})
    except:
        return {}

def upload_compressed_file(data: bytes, key: str, algorithm: str, 
                          original_metadata: Dict) -> None:
    """
    上传压缩文件
    """
    # 准备上传参数
    put_params = {
        'Bucket': TARGET_BUCKET,
        'Key': key,
        'Body': data,
        'ContentEncoding': COMPRESSION_ALGORITHMS.get(algorithm, {}).get('content_encoding', 'gzip'),
        'Metadata': {
            **original_metadata,
            'original-compression': 'none',
            'compression-algorithm': algorithm,
            'compression-timestamp': datetime.utcnow().isoformat()
        }
    }
    
    # 设置Content-Type
    content_type, _ = mimetypes.guess_type(key.replace('.gz', '').replace('.bz2', '').replace('.xz', ''))
    if content_type:
        put_params['ContentType'] = content_type
    
    # 加密设置
    if ENABLE_ENCRYPTION:
        if KMS_KEY_ID:
            put_params['ServerSideEncryption'] = 'aws:kms'
            put_params['SSEKMSKeyId'] = KMS_KEY_ID
        else:
            put_params['ServerSideEncryption'] = 'AES256'
    
    # 上传文件
    s3_client.put_object(**put_params)
    print(f"Uploaded compressed file to s3://{TARGET_BUCKET}/{key}")

def publish_metrics(result: Dict) -> None:
    """
    发布CloudWatch指标
    """
    try:
        metrics = [
            {
                'MetricName': 'BytesProcessed',
                'Value': result['original_size'],
                'Unit': 'Bytes'
            },
            {
                'MetricName': 'BytesSaved',
                'Value': result['space_saved'],
                'Unit': 'Bytes'
            },
            {
                'MetricName': 'CompressionRatio',
                'Value': result['compression_ratio'],
                'Unit': 'None'
            },
            {
                'MetricName': 'FilesCompressed',
                'Value': 1,
                'Unit': 'Count'
            }
        ]
        
        for metric in metrics:
            cloudwatch_client.put_metric_data(
                Namespace='CompressionMetrics',
                MetricData=[
                    {
                        **metric,
                        'Timestamp': datetime.utcnow(),
                        'Dimensions': [
                            {
                                'Name': 'Algorithm',
                                'Value': result['algorithm']
                            }
                        ]
                    }
                ]
            )
    except Exception as e:
        print(f"Failed to publish metrics: {e}")
