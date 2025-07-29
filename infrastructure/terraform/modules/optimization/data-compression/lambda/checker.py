#!/usr/bin/env python3
"""
Compression Checker Lambda Function
检查文件是否需要压缩并推荐压缩算法
"""

import json
import os
import boto3
from typing import Dict, Optional

# 初始化AWS客户端
s3_client = boto3.client('s3')

# 环境变量
MIN_FILE_SIZE = int(os.environ.get('MIN_FILE_SIZE', '1048576'))  # 1MB
COMPRESSIBLE_TYPES = json.loads(os.environ.get('COMPRESSIBLE_TYPES', '[]'))

# 不需要压缩的文件类型
EXCLUDED_TYPES = [
    # 已经压缩的格式
    '.gz', '.bz2', '.xz', '.zst', '.lz4', '.zip', '.rar', '.7z',
    # 媒体格式（通常已经压缩）
    '.jpg', '.jpeg', '.png', '.gif', '.webp', '.mp4', '.mp3', '.avi', '.mkv',
    # 其他二进制格式
    '.exe', '.dll', '.so', '.dylib'
]

# 文件类型与压缩算法映射
FILE_TYPE_ALGORITHMS = {
    'text': {
        'extensions': ['.txt', '.log', '.csv', '.tsv', '.md', '.rst'],
        'algorithm': 'gzip',
        'expected_ratio': 0.3  # 预期压缩到原大小的30%
    },
    'json': {
        'extensions': ['.json', '.jsonl'],
        'algorithm': 'gzip',
        'expected_ratio': 0.2
    },
    'xml': {
        'extensions': ['.xml', '.xhtml', '.svg'],
        'algorithm': 'gzip',
        'expected_ratio': 0.25
    },
    'code': {
        'extensions': ['.py', '.js', '.java', '.cpp', '.c', '.h', '.go', '.rs'],
        'algorithm': 'gzip',
        'expected_ratio': 0.35
    },
    'web': {
        'extensions': ['.html', '.css', '.js', '.map'],
        'algorithm': 'gzip',
        'expected_ratio': 0.3
    },
    'database': {
        'extensions': ['.sql', '.dump'],
        'algorithm': 'zstd',
        'expected_ratio': 0.25
    },
    'documents': {
        'extensions': ['.pdf', '.doc', '.docx', '.odt'],
        'algorithm': 'zstd',
        'expected_ratio': 0.8  # 文档通常已有一定压缩
    },
    'data': {
        'extensions': ['.parquet', '.avro', '.orc'],
        'algorithm': 'lz4',  # 快速压缩解压
        'expected_ratio': 0.7
    }
}

def handler(event, context):
    """
    Lambda处理函数
    """
    bucket = event.get('bucket')
    key = event.get('key')
    size = event.get('size', 0)
    
    if not bucket or not key:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'Missing bucket or key'})
        }
    
    # 如果没有提供大小，从 S3 获取
    if size == 0:
        try:
            response = s3_client.head_object(Bucket=bucket, Key=key)
            size = response['ContentLength']
        except Exception as e:
            print(f"Failed to get object size: {e}")
            return {
                'statusCode': 500,
                'body': json.dumps({'error': 'Failed to get object size'})
            }
    
    # 检查是否应该压缩
    should_compress, recommendation = check_compression(key, size)
    
    result = {
        'bucket': bucket,
        'key': key,
        'size': size,
        'shouldCompress': should_compress,
        'recommendation': recommendation
    }
    
    if should_compress:
        result['recommendedCompression'] = recommendation['algorithm']
        result['expectedCompressionRatio'] = recommendation['expected_ratio']
        result['expectedSizeAfterCompression'] = int(size * recommendation['expected_ratio'])
        result['expectedSpaceSaved'] = size - result['expectedSizeAfterCompression']
    
    return result

def check_compression(key: str, size: int) -> tuple[bool, Optional[Dict]]:
    """
    检查文件是否应该压缩
    
    Returns:
        (should_compress, recommendation)
    """
    # 检查文件大小
    if size < MIN_FILE_SIZE:
        return False, {
            'reason': 'File too small',
            'min_size': MIN_FILE_SIZE
        }
    
    # 获取文件扩展名
    _, ext = os.path.splitext(key.lower())
    
    # 检查是否在排除列表中
    if ext in EXCLUDED_TYPES:
        return False, {
            'reason': 'File type excluded',
            'extension': ext
        }
    
    # 检查是否在可压缩类型列表中
    if COMPRESSIBLE_TYPES and ext not in COMPRESSIBLE_TYPES:
        return False, {
            'reason': 'File type not in compressible list',
            'extension': ext
        }
    
    # 查找最佳压缩算法
    recommendation = find_best_algorithm(ext, size)
    
    if recommendation:
        return True, recommendation
    else:
        # 如果没有找到特定算法，但文件较大，使用默认压缩
        if size > 10 * 1024 * 1024:  # 10MB
            return True, {
                'algorithm': 'gzip',
                'expected_ratio': 0.5,
                'reason': 'Large file, using default compression'
            }
        else:
            return False, {
                'reason': 'No suitable compression algorithm found',
                'extension': ext
            }

def find_best_algorithm(extension: str, size: int) -> Optional[Dict]:
    """
    查找最佳压缩算法
    """
    for file_type, config in FILE_TYPE_ALGORITHMS.items():
        if extension in config['extensions']:
            return {
                'algorithm': config['algorithm'],
                'expected_ratio': config['expected_ratio'],
                'file_type': file_type,
                'reason': f'Matched file type: {file_type}'
            }
    
    # 基于文件大小选择算法
    if size > 100 * 1024 * 1024:  # > 100MB
        # 大文件使用快速算法
        return {
            'algorithm': 'lz4',
            'expected_ratio': 0.6,
            'reason': 'Large file, using fast compression'
        }
    elif size > 10 * 1024 * 1024:  # > 10MB
        # 中等文件使用平衡算法
        return {
            'algorithm': 'zstd',
            'expected_ratio': 0.5,
            'reason': 'Medium file, using balanced compression'
        }
    
    return None

def estimate_compression_time(size: int, algorithm: str) -> float:
    """
    估计压缩时间（秒）
    """
    # 基于算法的压缩速度（MB/s）
    compression_speeds = {
        'gzip': 50,    # 50 MB/s
        'bzip2': 10,   # 10 MB/s
        'xz': 5,       # 5 MB/s
        'zstd': 200,   # 200 MB/s
        'lz4': 500     # 500 MB/s
    }
    
    speed = compression_speeds.get(algorithm, 50)
    size_mb = size / (1024 * 1024)
    
    return size_mb / speed

def estimate_cost_savings(size: int, expected_ratio: float) -> Dict:
    """
    估计成本节省
    """
    # S3存储成本（每GB/月）
    storage_cost_per_gb = 0.023
    
    size_gb = size / (1024 ** 3)
    compressed_size_gb = size_gb * expected_ratio
    saved_gb = size_gb - compressed_size_gb
    
    monthly_savings = saved_gb * storage_cost_per_gb
    yearly_savings = monthly_savings * 12
    
    return {
        'original_size_gb': round(size_gb, 3),
        'compressed_size_gb': round(compressed_size_gb, 3),
        'space_saved_gb': round(saved_gb, 3),
        'monthly_savings_usd': round(monthly_savings, 2),
        'yearly_savings_usd': round(yearly_savings, 2)
    }
