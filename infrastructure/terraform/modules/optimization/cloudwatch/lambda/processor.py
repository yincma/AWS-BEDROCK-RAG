#!/usr/bin/env python3
"""
Log Processor Lambda Function
处理和过滤日志数据，在存储前进行优化
"""

import json
import os
import re
import hashlib
import base64
from typing import Dict, List, Optional, Set
from datetime import datetime
import gzip
import io

# 环境变量
FILTER_RULES = json.loads(os.environ.get('FILTER_RULES', '[]'))
ENABLE_DEDUPLICATION = os.environ.get('ENABLE_DEDUPLICATION', 'true').lower() == 'true'

# 预编译过滤规则
COMPILED_RULES = []
for rule in FILTER_RULES:
    if rule.get('field') == 'message' and rule.get('operator') == 'regex':
        rule['compiled_pattern'] = re.compile(rule['value'])
    COMPILED_RULES.append(rule)

def handler(event, context):
    """
    Lambda处理函数 - 处理Kinesis Firehose数据
    """
    output = []
    seen_hashes = set() if ENABLE_DEDUPLICATION else None
    
    # 处理每条记录
    for record in event['records']:
        # 解码数据
        payload = base64.b64decode(record['data'])
        
        # 尝试解析JSON
        try:
            log_data = json.loads(payload)
        except json.JSONDecodeError:
            # 如果不是JSON，作为纯文本处理
            log_data = {'message': payload.decode('utf-8', errors='ignore')}
        
        # 应用过滤规则
        if should_filter_log(log_data):
            # 记录被过滤
            result = {
                'recordId': record['recordId'],
                'result': 'Dropped'
            }
        else:
            # 处理日志
            processed_log = process_log(log_data)
            
            # 去重
            if ENABLE_DEDUPLICATION:
                log_hash = get_log_hash(processed_log)
                if log_hash in seen_hashes:
                    result = {
                        'recordId': record['recordId'],
                        'result': 'Dropped'
                    }
                else:
                    seen_hashes.add(log_hash)
                    result = process_and_encode_log(record['recordId'], processed_log)
            else:
                result = process_and_encode_log(record['recordId'], processed_log)
        
        output.append(result)
    
    # 返回处理结果
    stats = {
        'total_records': len(event['records']),
        'processed_records': sum(1 for r in output if r['result'] == 'Ok'),
        'dropped_records': sum(1 for r in output if r['result'] == 'Dropped')
    }
    
    print(json.dumps(stats))
    return {'records': output}

def should_filter_log(log_data: Dict) -> bool:
    """
    根据过滤规则判断是否应该过滤日志
    """
    for rule in COMPILED_RULES:
        field = rule.get('field')
        operator = rule.get('operator')
        value = rule.get('value')
        action = rule.get('action', 'exclude')
        
        # 获取字段值
        field_value = log_data.get(field)
        if field_value is None:
            continue
        
        # 应用操作符
        matches = False
        if operator == 'equals':
            matches = str(field_value) == value
        elif operator == 'contains':
            matches = value in str(field_value)
        elif operator == 'regex':
            matches = bool(rule.get('compiled_pattern', re.compile(value)).search(str(field_value)))
        elif operator == 'startswith':
            matches = str(field_value).startswith(value)
        elif operator == 'endswith':
            matches = str(field_value).endswith(value)
        elif operator == 'greater_than':
            try:
                matches = float(field_value) > float(value)
            except ValueError:
                matches = False
        elif operator == 'less_than':
            try:
                matches = float(field_value) < float(value)
            except ValueError:
                matches = False
        
        # 根据动作决定
        if action == 'exclude' and matches:
            return True  # 过滤掉
        elif action == 'include' and not matches:
            return True  # 不包含，过滤掉
    
    return False

def process_log(log_data: Dict) -> Dict:
    """
    处理日志数据，添加元数据和优化
    """
    # 添加处理时间戳
    if '@timestamp' not in log_data:
        log_data['@timestamp'] = datetime.utcnow().isoformat() + 'Z'
    
    # 添加处理元数据
    log_data['@processed'] = {
        'timestamp': datetime.utcnow().isoformat() + 'Z',
        'processor': 'log-processor-lambda',
        'version': '1.0'
    }
    
    # 提取日志级别
    if 'level' not in log_data and 'message' in log_data:
        level = extract_log_level(log_data['message'])
        if level:
            log_data['level'] = level
    
    # 清理空字段
    cleaned_log = {k: v for k, v in log_data.items() if v is not None and v != ''}
    
    # 限制消息长度
    if 'message' in cleaned_log and len(cleaned_log['message']) > 10000:
        cleaned_log['message'] = cleaned_log['message'][:10000] + '... [truncated]'
    
    return cleaned_log

def extract_log_level(message: str) -> Optional[str]:
    """
    从日志消息中提取日志级别
    """
    level_patterns = [
        (r'\bERROR\b', 'ERROR'),
        (r'\bWARN(?:ING)?\b', 'WARN'),
        (r'\bINFO\b', 'INFO'),
        (r'\bDEBUG\b', 'DEBUG'),
        (r'\bTRACE\b', 'TRACE'),
        (r'\bFATAL\b', 'FATAL')
    ]
    
    for pattern, level in level_patterns:
        if re.search(pattern, message, re.IGNORECASE):
            return level
    
    return None

def get_log_hash(log_data: Dict) -> str:
    """
    计算日志的哈希值用于去重
    """
    # 使用关键字段生成哈希
    hash_fields = ['message', 'level', 'logger', 'thread']
    hash_data = {}
    
    for field in hash_fields:
        if field in log_data:
            hash_data[field] = log_data[field]
    
    # 如果没有关键字段，使用整个日志
    if not hash_data:
        hash_data = log_data
    
    # 计算哈希
    hash_string = json.dumps(hash_data, sort_keys=True)
    return hashlib.md5(hash_string.encode()).hexdigest()

def process_and_encode_log(record_id: str, log_data: Dict) -> Dict:
    """
    处理并编码日志以供输出
    """
    try:
        # 转换为JSON并添加换行符
        processed_data = json.dumps(log_data, separators=(',', ':')) + '\n'
        
        # 编码为base64
        encoded_data = base64.b64encode(processed_data.encode('utf-8')).decode('utf-8')
        
        return {
            'recordId': record_id,
            'result': 'Ok',
            'data': encoded_data
        }
    except Exception as e:
        print(f"Error processing record {record_id}: {e}")
        return {
            'recordId': record_id,
            'result': 'ProcessingFailed'
        }

def compress_logs(logs: List[Dict]) -> bytes:
    """
    压缩日志数据
    """
    # 将日志列表转换为NDJSON格式
    ndjson = '\n'.join(json.dumps(log) for log in logs)
    
    # 使用gzip压缩
    compressed = io.BytesIO()
    with gzip.GzipFile(fileobj=compressed, mode='wb', compresslevel=6) as gz:
        gz.write(ndjson.encode('utf-8'))
    
    return compressed.getvalue()

def get_log_statistics(logs: List[Dict]) -> Dict:
    """
    计算日志统计信息
    """
    stats = {
        'total_count': len(logs),
        'total_size': sum(len(json.dumps(log)) for log in logs),
        'level_distribution': {},
        'top_loggers': {},
        'avg_message_length': 0
    }
    
    # 统计日志级别分布
    for log in logs:
        level = log.get('level', 'UNKNOWN')
        stats['level_distribution'][level] = stats['level_distribution'].get(level, 0) + 1
        
        # 统计logger分布
        logger = log.get('logger', 'unknown')
        stats['top_loggers'][logger] = stats['top_loggers'].get(logger, 0) + 1
    
    # 计算平均消息长度
    message_lengths = [len(log.get('message', '')) for log in logs]
    if message_lengths:
        stats['avg_message_length'] = sum(message_lengths) / len(message_lengths)
    
    # 只保留前10个logger
    stats['top_loggers'] = dict(sorted(
        stats['top_loggers'].items(), 
        key=lambda x: x[1], 
        reverse=True
    )[:10])
    
    return stats
