"""
Storage Cost Calculator Lambda Function

Calculates daily storage costs and publishes metrics to CloudWatch.
"""

import os
import json
import boto3
from datetime import datetime, timedelta
from typing import Dict, List

s3_client = boto3.client('s3')
logs_client = boto3.client('logs')
cloudwatch_client = boto3.client('cloudwatch')
ce_client = boto3.client('ce')

METRIC_NAMESPACE = os.environ['METRIC_NAMESPACE']
S3_PRICING = json.loads(os.environ['S3_PRICING'])
LOGS_PRICING = json.loads(os.environ['LOGS_PRICING'])


def handler(event, context):
    """
    Main handler for cost calculation.
    """
    print(f"Starting daily cost calculation: {json.dumps(event)}")
    
    # Calculate S3 costs
    s3_costs = calculate_s3_costs()
    
    # Calculate CloudWatch Logs costs
    logs_costs = calculate_logs_costs()
    
    # Calculate total costs
    total_daily_cost = s3_costs['total_daily_cost'] + logs_costs['total_daily_cost']
    
    # Publish metrics
    publish_cost_metrics({
        's3_storage_cost': s3_costs['total_daily_cost'],
        's3_storage_gb': s3_costs['total_storage_gb'],
        's3_objects_count': s3_costs['total_objects'],
        'logs_storage_cost': logs_costs['total_daily_cost'],
        'logs_storage_gb': logs_costs['total_storage_gb'],
        'logs_groups_count': logs_costs['total_log_groups'],
        'total_storage_cost': total_daily_cost
    })
    
    # Get cost trends from Cost Explorer
    cost_trends = get_cost_trends()
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            's3_costs': s3_costs,
            'logs_costs': logs_costs,
            'total_daily_cost': total_daily_cost,
            'cost_trends': cost_trends,
            'timestamp': datetime.utcnow().isoformat()
        })
    }


def calculate_s3_costs() -> Dict:
    """
    Calculate S3 storage costs.
    """
    total_storage_gb = 0
    total_objects = 0
    total_daily_cost = 0
    bucket_costs = []
    
    # List all buckets
    response = s3_client.list_buckets()
    
    for bucket in response['Buckets']:
        bucket_name = bucket['Name']
        
        try:
            # Get bucket metrics
            bucket_size_response = cloudwatch_client.get_metric_statistics(
                Namespace='AWS/S3',
                MetricName='BucketSizeBytes',
                Dimensions=[
                    {'Name': 'BucketName', 'Value': bucket_name},
                    {'Name': 'StorageType', 'Value': 'StandardStorage'}
                ],
                StartTime=datetime.utcnow() - timedelta(days=1),
                EndTime=datetime.utcnow(),
                Period=86400,
                Statistics=['Average']
            )
            
            object_count_response = cloudwatch_client.get_metric_statistics(
                Namespace='AWS/S3',
                MetricName='NumberOfObjects',
                Dimensions=[
                    {'Name': 'BucketName', 'Value': bucket_name},
                    {'Name': 'StorageType', 'Value': 'AllStorageTypes'}
                ],
                StartTime=datetime.utcnow() - timedelta(days=1),
                EndTime=datetime.utcnow(),
                Period=86400,
                Statistics=['Average']
            )
            
            # Get storage class distribution
            storage_class_costs = get_bucket_storage_class_distribution(bucket_name)
            
            if bucket_size_response['Datapoints']:
                bucket_size_bytes = bucket_size_response['Datapoints'][0]['Average']
                bucket_size_gb = bucket_size_bytes / (1024**3)
                total_storage_gb += bucket_size_gb
                
                # Calculate daily cost
                daily_cost = storage_class_costs['total_daily_cost']
                total_daily_cost += daily_cost
                
                bucket_costs.append({
                    'bucket': bucket_name,
                    'size_gb': bucket_size_gb,
                    'daily_cost': daily_cost,
                    'storage_classes': storage_class_costs['distribution']
                })
            
            if object_count_response['Datapoints']:
                object_count = int(object_count_response['Datapoints'][0]['Average'])
                total_objects += object_count
                
        except Exception as e:
            print(f"Error calculating costs for bucket {bucket_name}: {e}")
    
    return {
        'total_storage_gb': total_storage_gb,
        'total_objects': total_objects,
        'total_daily_cost': total_daily_cost,
        'bucket_costs': bucket_costs
    }


def get_bucket_storage_class_distribution(bucket_name: str) -> Dict:
    """
    Get storage class distribution for a bucket.
    """
    distribution = {}
    total_daily_cost = 0
    
    storage_classes = ['STANDARD', 'STANDARD_IA', 'GLACIER', 'DEEP_ARCHIVE']
    
    for storage_class in storage_classes:
        try:
            response = cloudwatch_client.get_metric_statistics(
                Namespace='AWS/S3',
                MetricName='BucketSizeBytes',
                Dimensions=[
                    {'Name': 'BucketName', 'Value': bucket_name},
                    {'Name': 'StorageType', 'Value': f'{storage_class}Storage'}
                ],
                StartTime=datetime.utcnow() - timedelta(days=1),
                EndTime=datetime.utcnow(),
                Period=86400,
                Statistics=['Average']
            )
            
            if response['Datapoints']:
                size_bytes = response['Datapoints'][0]['Average']
                size_gb = size_bytes / (1024**3)
                
                # Calculate daily cost (monthly price / 30)
                daily_cost = (size_gb * S3_PRICING.get(storage_class, 0.023)) / 30
                
                distribution[storage_class] = {
                    'size_gb': size_gb,
                    'daily_cost': daily_cost
                }
                total_daily_cost += daily_cost
                
        except Exception:
            pass
    
    return {
        'distribution': distribution,
        'total_daily_cost': total_daily_cost
    }


def calculate_logs_costs() -> Dict:
    """
    Calculate CloudWatch Logs costs.
    """
    total_storage_gb = 0
    total_log_groups = 0
    total_daily_cost = 0
    log_group_costs = []
    
    paginator = logs_client.get_paginator('describe_log_groups')
    
    for page in paginator.paginate():
        for log_group in page['logGroups']:
            total_log_groups += 1
            
            # Get stored bytes
            stored_bytes = log_group.get('storedBytes', 0)
            storage_gb = stored_bytes / (1024**3)
            total_storage_gb += storage_gb
            
            # Calculate storage cost (monthly price / 30)
            storage_cost = (storage_gb * LOGS_PRICING['storage']) / 30
            
            # Estimate ingestion cost (assume 10% daily growth)
            estimated_daily_ingestion_gb = storage_gb * 0.1
            ingestion_cost = estimated_daily_ingestion_gb * LOGS_PRICING['ingestion']
            
            daily_cost = storage_cost + ingestion_cost
            total_daily_cost += daily_cost
            
            log_group_costs.append({
                'log_group': log_group['logGroupName'],
                'storage_gb': storage_gb,
                'daily_cost': daily_cost,
                'retention_days': log_group.get('retentionInDays', 'Never expire')
            })
    
    return {
        'total_storage_gb': total_storage_gb,
        'total_log_groups': total_log_groups,
        'total_daily_cost': total_daily_cost,
        'log_group_costs': sorted(
            log_group_costs,
            key=lambda x: x['daily_cost'],
            reverse=True
        )[:10]  # Top 10 most expensive
    }


def publish_cost_metrics(metrics: Dict):
    """
    Publish cost metrics to CloudWatch.
    """
    metric_data = []
    
    for metric_name, value in metrics.items():
        metric_data.append({
            'MetricName': metric_name.replace('_', ' ').title().replace(' ', ''),
            'Value': value,
            'Unit': 'None' if 'count' in metric_name else 'Count',
            'Timestamp': datetime.utcnow()
        })
    
    # Publish in batches of 20 (CloudWatch limit)
    for i in range(0, len(metric_data), 20):
        batch = metric_data[i:i+20]
        
        cloudwatch_client.put_metric_data(
            Namespace=METRIC_NAMESPACE,
            MetricData=batch
        )
    
    print(f"Published {len(metric_data)} metrics to CloudWatch")


def get_cost_trends() -> Dict:
    """
    Get cost trends from AWS Cost Explorer.
    """
    end_date = datetime.utcnow().date()
    start_date = end_date - timedelta(days=30)
    
    try:
        response = ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='DAILY',
            Metrics=['UnblendedCost'],
            GroupBy=[
                {
                    'Type': 'DIMENSION',
                    'Key': 'SERVICE'
                }
            ],
            Filter={
                'Dimensions': {
                    'Key': 'SERVICE',
                    'Values': [
                        'Amazon Simple Storage Service',
                        'AmazonCloudWatch'
                    ]
                }
            }
        )
        
        # Process results
        trends = {
            's3': [],
            'cloudwatch': []
        }
        
        for result in response['ResultsByTime']:
            date = result['TimePeriod']['Start']
            
            for group in result['Groups']:
                service = group['Keys'][0]
                cost = float(group['Metrics']['UnblendedCost']['Amount'])
                
                if 'S3' in service:
                    trends['s3'].append({'date': date, 'cost': cost})
                elif 'CloudWatch' in service:
                    trends['cloudwatch'].append({'date': date, 'cost': cost})
        
        return trends
        
    except Exception as e:
        print(f"Error getting cost trends: {e}")
        return {'s3': [], 'cloudwatch': []}