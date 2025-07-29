"""
CloudWatch Logs Compressor Lambda Function

Exports and compresses CloudWatch logs to S3 for cost optimization.
"""

import os
import json
import boto3
import gzip
import time
from datetime import datetime, timedelta
from typing import List, Dict, Optional

logs_client = boto3.client('logs')
s3_client = boto3.client('s3')

ARCHIVE_BUCKET = os.environ['ARCHIVE_BUCKET']
COMPRESSION_LEVEL = int(os.environ.get('COMPRESSION_LEVEL', '9'))
DELETE_AFTER_DAYS = int(os.environ.get('DELETE_AFTER_DAYS', '7'))


def handler(event, context):
    """
    Main handler function for log compression.
    """
    print(f"Starting log compression job: {json.dumps(event)}")
    
    # Get all log groups
    log_groups = get_log_groups_to_process()
    
    results = []
    for log_group in log_groups:
        try:
            result = process_log_group(log_group)
            results.append(result)
        except Exception as e:
            print(f"Error processing log group {log_group}: {e}")
            results.append({
                'log_group': log_group,
                'status': 'error',
                'error': str(e)
            })
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'processed': len(results),
            'results': results
        })
    }


def get_log_groups_to_process() -> List[str]:
    """
    Get list of log groups that need processing.
    """
    log_groups = []
    
    paginator = logs_client.get_paginator('describe_log_groups')
    for page in paginator.paginate():
        for log_group in page['logGroups']:
            # Only process log groups with compression enabled (tagged)
            tags = get_log_group_tags(log_group['logGroupName'])
            if tags.get('CompressionEnabled') == 'true':
                log_groups.append(log_group['logGroupName'])
    
    return log_groups


def get_log_group_tags(log_group_name: str) -> Dict[str, str]:
    """
    Get tags for a log group.
    """
    try:
        response = logs_client.list_tags_log_group(logGroupName=log_group_name)
        return response.get('tags', {})
    except Exception:
        return {}


def process_log_group(log_group_name: str) -> Dict:
    """
    Process a single log group - export and compress old logs.
    """
    # Calculate time range (process logs older than DELETE_AFTER_DAYS)
    end_time = datetime.utcnow() - timedelta(days=DELETE_AFTER_DAYS)
    start_time = end_time - timedelta(days=1)  # Process 1 day at a time
    
    # Format timestamps
    start_timestamp = int(start_time.timestamp() * 1000)
    end_timestamp = int(end_time.timestamp() * 1000)
    
    # Check if there are logs in this time range
    log_streams = get_log_streams(log_group_name, start_timestamp, end_timestamp)
    if not log_streams:
        return {
            'log_group': log_group_name,
            'status': 'skipped',
            'reason': 'No logs in time range'
        }
    
    # Export logs to memory and compress
    compressed_logs = export_and_compress_logs(
        log_group_name, 
        log_streams, 
        start_timestamp, 
        end_timestamp
    )
    
    # Upload to S3
    s3_key = generate_s3_key(log_group_name, start_time)
    upload_to_s3(compressed_logs, s3_key)
    
    # Delete processed log streams (optional, based on retention policy)
    # delete_processed_streams(log_group_name, log_streams)
    
    return {
        'log_group': log_group_name,
        'status': 'success',
        'compressed_size': len(compressed_logs),
        's3_key': s3_key,
        'streams_processed': len(log_streams)
    }


def get_log_streams(log_group_name: str, start_time: int, end_time: int) -> List[str]:
    """
    Get log streams that have data in the specified time range.
    """
    streams = []
    
    paginator = logs_client.get_paginator('describe_log_streams')
    for page in paginator.paginate(
        logGroupName=log_group_name,
        orderBy='LastEventTime',
        descending=True
    ):
        for stream in page['logStreams']:
            # Check if stream has data in our time range
            if 'firstEventTime' in stream and 'lastEventTime' in stream:
                if stream['firstEventTime'] <= end_time and stream['lastEventTime'] >= start_time:
                    streams.append(stream['logStreamName'])
    
    return streams


def export_and_compress_logs(
    log_group_name: str, 
    log_streams: List[str], 
    start_time: int, 
    end_time: int
) -> bytes:
    """
    Export logs and compress them.
    """
    all_events = []
    
    # Fetch logs from each stream
    for stream_name in log_streams:
        paginator = logs_client.get_paginator('filter_log_events')
        
        for page in paginator.paginate(
            logGroupName=log_group_name,
            logStreamNames=[stream_name],
            startTime=start_time,
            endTime=end_time
        ):
            for event in page.get('events', []):
                all_events.append({
                    'timestamp': event['timestamp'],
                    'message': event['message'],
                    'stream': stream_name
                })
    
    # Sort events by timestamp
    all_events.sort(key=lambda x: x['timestamp'])
    
    # Convert to JSONL format (one JSON object per line)
    jsonl_data = '\n'.join(json.dumps(event) for event in all_events)
    
    # Compress with gzip
    compressed_data = gzip.compress(
        jsonl_data.encode('utf-8'), 
        compresslevel=COMPRESSION_LEVEL
    )
    
    print(f"Compressed {len(jsonl_data)} bytes to {len(compressed_data)} bytes "
          f"({len(compressed_data) / len(jsonl_data) * 100:.1f}% of original)")
    
    return compressed_data


def generate_s3_key(log_group_name: str, date: datetime) -> str:
    """
    Generate S3 key for the compressed log file.
    """
    # Remove leading slash from log group name
    clean_name = log_group_name.lstrip('/')
    
    # Create hierarchical structure
    return (f"logs/{clean_name}/"
            f"year={date.year}/month={date.month:02d}/day={date.day:02d}/"
            f"{clean_name}-{date.strftime('%Y%m%d')}.json.gz")


def upload_to_s3(data: bytes, s3_key: str) -> None:
    """
    Upload compressed data to S3.
    """
    s3_client.put_object(
        Bucket=ARCHIVE_BUCKET,
        Key=s3_key,
        Body=data,
        ContentType='application/gzip',
        ContentEncoding='gzip',
        StorageClass='GLACIER',  # Use Glacier for immediate cost savings
        ServerSideEncryption='AES256',
        Metadata={
            'compression-level': str(COMPRESSION_LEVEL),
            'original-format': 'cloudwatch-logs',
            'compressed-at': datetime.utcnow().isoformat()
        }
    )
    
    print(f"Uploaded compressed logs to s3://{ARCHIVE_BUCKET}/{s3_key}")


def delete_processed_streams(log_group_name: str, log_streams: List[str]) -> None:
    """
    Delete processed log streams (optional, use with caution).
    """
    # This is commented out by default for safety
    # Uncomment only if you're sure you want to delete logs after archiving
    
    # for stream_name in log_streams:
    #     try:
    #         logs_client.delete_log_stream(
    #             logGroupName=log_group_name,
    #             logStreamName=stream_name
    #         )
    #         print(f"Deleted log stream: {stream_name}")
    #     except Exception as e:
    #         print(f"Error deleting stream {stream_name}: {e}")
    pass