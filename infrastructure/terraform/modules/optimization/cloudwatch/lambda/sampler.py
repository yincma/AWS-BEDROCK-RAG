#!/usr/bin/env python3
"""
Log Sampler Lambda Function
实现日志采样以减少CloudWatch成本
"""

import json
import os
import random
import re
import boto3
import base64
import gzip
from typing import Dict, List, Optional
from datetime import datetime

# 初始化AWS客户端
logs_client = boto3.client('logs')

# 环境变量
SAMPLING_RATE = float(os.environ.get('SAMPLING_RATE', '0.1'))
SAMPLING_RULES = json.loads(os.environ.get('SAMPLING_RULES', '{}'))
DESTINATION_GROUP = os.environ.get('DESTINATION_GROUP', '/aws/lambda/sampled')

# 预编译正则表达式
RULE_PATTERNS = {
    rule_name: re.compile(rule_config['pattern'], re.IGNORECASE)
    for rule_name, rule_config in SAMPLING_RULES.items()
}

def handler(event, context):
    """
    Lambda处理函数 - 处理CloudWatch Logs事件
    """
    # 解码日志数据
    log_data = json.loads(gzip.decompress(base64.b64decode(event['awslogs']['data'])))
    
    log_group = log_data['logGroup']
    log_stream = log_data['logStream']
    log_events = log_data['logEvents']
    
    print(f"Processing {len(log_events)} events from {log_group}/{log_stream}")
    
    # 对日志进行采样
    sampled_events = sample_logs(log_events)
    
    if not sampled_events:
        print("No events to forward after sampling")
        return {'statusCode': 200, 'body': json.dumps({'sampled': 0})}
    
    # 将采样后的日志发送到目标日志组
    try:
        forward_sampled_logs(
            sampled_events, 
            f"{DESTINATION_GROUP}/{log_group.replace('/', '-')}",
            log_stream
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'original_count': len(log_events),
                'sampled_count': len(sampled_events),
                'sampling_ratio': len(sampled_events) / len(log_events) if log_events else 0
            })
        }
    except Exception as e:
        print(f"Error forwarding logs: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def sample_logs(log_events: List[Dict]) -> List[Dict]:
    """
    对日志事件进行采样
    """
    sampled_events = []
    
    for event in log_events:
        message = event.get('message', '')
        
        # 检查是否匹配特定规则
        sampling_rate = get_sampling_rate(message)
        
        # 根据采样率决定是否保留
        if should_sample(sampling_rate):
            sampled_events.append(event)
    
    return sampled_events

def get_sampling_rate(message: str) -> float:
    """
    根据日志内容确定采样率
    """
    # 检查每个采样规则
    for rule_name, pattern in RULE_PATTERNS.items():
        if pattern.search(message):
            return SAMPLING_RULES[rule_name]['rate']
    
    # 使用默认采样率
    return SAMPLING_RATE

def should_sample(sampling_rate: float) -> bool:
    """
    根据采样率决定是否采样
    """
    if sampling_rate >= 1.0:
        return True
    elif sampling_rate <= 0.0:
        return False
    else:
        return random.random() < sampling_rate

def forward_sampled_logs(events: List[Dict], log_group: str, log_stream: str) -> None:
    """
    将采样后的日志转发到目标日志组
    """
    # 确保日志组存在
    ensure_log_group_exists(log_group)
    
    # 确保日志流存在
    stream_name = f"{log_stream}-sampled-{datetime.utcnow().strftime('%Y%m%d%H%M%S')}"
    ensure_log_stream_exists(log_group, stream_name)
    
    # 准备日志事件
    log_events = [
        {
            'timestamp': event['timestamp'],
            'message': event['message']
        }
        for event in sorted(events, key=lambda x: x['timestamp'])
    ]
    
    # 发送日志
    logs_client.put_log_events(
        logGroupName=log_group,
        logStreamName=stream_name,
        logEvents=log_events
    )
    
    print(f"Forwarded {len(events)} sampled events to {log_group}/{stream_name}")

def ensure_log_group_exists(log_group: str) -> None:
    """
    确保日志组存在
    """
    try:
        logs_client.create_log_group(logGroupName=log_group)
        print(f"Created log group: {log_group}")
    except logs_client.exceptions.ResourceAlreadyExistsException:
        pass

def ensure_log_stream_exists(log_group: str, log_stream: str) -> None:
    """
    确保日志流存在
    """
    try:
        logs_client.create_log_stream(
            logGroupName=log_group,
            logStreamName=log_stream
        )
        print(f"Created log stream: {log_stream}")
    except logs_client.exceptions.ResourceAlreadyExistsException:
        pass

def get_log_statistics(log_events: List[Dict]) -> Dict:
    """
    获取日志统计信息
    """
    stats = {
        'total_count': len(log_events),
        'total_size': sum(len(event.get('message', '')) for event in log_events),
        'level_counts': {
            'ERROR': 0,
            'WARN': 0,
            'INFO': 0,
            'DEBUG': 0,
            'OTHER': 0
        }
    }
    
    for event in log_events:
        message = event.get('message', '').upper()
        if 'ERROR' in message:
            stats['level_counts']['ERROR'] += 1
        elif 'WARN' in message:
            stats['level_counts']['WARN'] += 1
        elif 'INFO' in message:
            stats['level_counts']['INFO'] += 1
        elif 'DEBUG' in message:
            stats['level_counts']['DEBUG'] += 1
        else:
            stats['level_counts']['OTHER'] += 1
    
    return stats
