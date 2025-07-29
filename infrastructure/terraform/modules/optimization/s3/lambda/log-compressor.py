#!/usr/bin/env python3
"""
CloudWatch Log Compressor Lambda Function
压缩CloudWatch日志并归档到S3，实现存储成本优化
"""

import base64
import gzip
import json
import os
import boto3
from datetime import datetime
import io

# 初始化AWS客户端
s3_client = boto3.client('s3')
kms_client = boto3.client('kms')

# 环境变量
ARCHIVE_BUCKET = os.environ.get('ARCHIVE_BUCKET')
COMPRESSION_LEVEL = int(os.environ.get('COMPRESSION_LEVEL', '6'))
ENCRYPTION_KEY_ID = os.environ.get('ENCRYPTION_KEY_ID', '')

def handler(event, context):
    """
    Lambda处理函数，接收CloudWatch Logs数据并压缩归档
    """
    print(f"Processing {len(event['logEvents'])} log events")
    
    # 解码日志数据
    log_data = base64.b64decode(event['awslogs']['data'])
    log_json = json.loads(gzip.decompress(log_data))
    
    log_group = log_json['logGroup']
    log_stream = log_json['logStream']
    
    # 准备压缩数据
    compressed_logs = compress_logs(log_json)
    
    # 生成S3键
    timestamp = datetime.utcnow()
    s3_key = f"compressed-logs/{log_group}/{timestamp.year}/{timestamp.month:02d}/{timestamp.day:02d}/{log_stream}-{timestamp.isoformat()}.gz"
    
    # 上传到S3
    upload_to_s3(compressed_logs, s3_key)
    
    # 返回处理统计
    return {
        'statusCode': 200,
        'body': json.dumps({
            'processed_events': len(log_json['logEvents']),
            'compressed_size': len(compressed_logs),
            's3_key': s3_key
        })
    }

def compress_logs(log_json):
    """
    压缩日志数据
    """
    # 准备日志内容
    log_content = io.StringIO()
    
    # 添加元数据
    log_content.write(f"# Log Group: {log_json['logGroup']}\n")
    log_content.write(f"# Log Stream: {log_json['logStream']}\n")
    log_content.write(f"# Owner: {log_json['owner']}\n")
    log_content.write(f"# Message Type: {log_json['messageType']}\n")
    log_content.write(f"# Subscription Filters: {', '.join(log_json['subscriptionFilters'])}\n")
    log_content.write("# " + "=" * 50 + "\n\n")
    
    # 添加日志事件
    for event in log_json['logEvents']:
        timestamp = datetime.fromtimestamp(event['timestamp'] / 1000)
        log_content.write(f"[{timestamp.isoformat()}] {event['message']}\n")
    
    # 压缩内容
    compressed = io.BytesIO()
    with gzip.GzipFile(fileobj=compressed, mode='wb', compresslevel=COMPRESSION_LEVEL) as gz:
        gz.write(log_content.getvalue().encode('utf-8'))
    
    return compressed.getvalue()

def upload_to_s3(data, s3_key):
    """
    上传压缩数据到S3
    """
    put_params = {
        'Bucket': ARCHIVE_BUCKET,
        'Key': s3_key,
        'Body': data,
        'ContentType': 'application/gzip',
        'ContentEncoding': 'gzip',
        'Metadata': {
            'compression-level': str(COMPRESSION_LEVEL),
            'original-source': 'cloudwatch-logs',
            'compressed-at': datetime.utcnow().isoformat()
        }
    }
    
    # 如果配置了KMS加密
    if ENCRYPTION_KEY_ID:
        put_params['ServerSideEncryption'] = 'aws:kms'
        put_params['SSEKMSKeyId'] = ENCRYPTION_KEY_ID
    
    # 上传文件
    response = s3_client.put_object(**put_params)
    
    print(f"Successfully uploaded to s3://{ARCHIVE_BUCKET}/{s3_key}")
    print(f"ETag: {response['ETag']}")
    
    return response

def get_compression_stats(original_size, compressed_size):
    """
    计算压缩统计信息
    """
    compression_ratio = compressed_size / original_size if original_size > 0 else 0
    space_saved = original_size - compressed_size
    percentage_saved = (1 - compression_ratio) * 100
    
    return {
        'original_size': original_size,
        'compressed_size': compressed_size,
        'compression_ratio': round(compression_ratio, 3),
        'space_saved': space_saved,
        'percentage_saved': round(percentage_saved, 1)
    }
