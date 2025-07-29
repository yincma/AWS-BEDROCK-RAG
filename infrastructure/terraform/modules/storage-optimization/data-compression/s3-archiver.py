"""
S3 Archiver Lambda Function

Moves old files to archive storage classes for cost optimization.
"""

import os
import json
import boto3
from datetime import datetime, timedelta
from typing import Dict, List, Optional
import concurrent.futures

s3_client = boto3.client('s3')

ARCHIVE_PREFIX = os.environ.get('ARCHIVE_PREFIX', 'archive/')
TAG_ARCHIVED = os.environ.get('TAG_ARCHIVED', 'true').lower() == 'true'
MAX_WORKERS = int(os.environ.get('MAX_WORKERS', '10'))


def handler(event, context):
    """
    Main Lambda handler for S3 archival.
    """
    print(f"Processing archival event: {json.dumps(event)}")
    
    bucket_name = event['bucket_name']
    archive_after_days = event.get('archive_after_days', 30)
    archive_prefix = event.get('archive_prefix', ARCHIVE_PREFIX)
    delete_after_archive = event.get('delete_after_archive', False)
    
    # Calculate cutoff date
    cutoff_date = datetime.utcnow() - timedelta(days=archive_after_days)
    
    # Process bucket
    results = archive_old_files(
        bucket_name,
        cutoff_date,
        archive_prefix,
        delete_after_archive
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'bucket': bucket_name,
            'processed': len(results),
            'archived': len([r for r in results if r['status'] == 'archived']),
            'results': results
        })
    }


def archive_old_files(
    bucket_name: str,
    cutoff_date: datetime,
    archive_prefix: str,
    delete_after_archive: bool
) -> List[Dict]:
    """
    Archive files older than cutoff date.
    """
    results = []
    files_to_archive = []
    
    paginator = s3_client.get_paginator('list_objects_v2')
    
    # Find files to archive
    for page in paginator.paginate(Bucket=bucket_name):
        if 'Contents' not in page:
            continue
        
        for obj in page['Contents']:
            key = obj['Key']
            last_modified = obj['LastModified'].replace(tzinfo=None)
            
            # Skip if already in archive prefix
            if key.startswith(archive_prefix):
                continue
            
            # Check if file is old enough
            if last_modified < cutoff_date:
                # Check current storage class
                storage_class = obj.get('StorageClass', 'STANDARD')
                
                # Only archive if not already in archive storage
                if storage_class in ['STANDARD', 'STANDARD_IA']:
                    files_to_archive.append({
                        'key': key,
                        'size': obj['Size'],
                        'last_modified': last_modified,
                        'storage_class': storage_class
                    })
    
    # Process files in parallel
    with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        future_to_file = {
            executor.submit(
                archive_single_file,
                bucket_name,
                file_info,
                archive_prefix,
                delete_after_archive
            ): file_info
            for file_info in files_to_archive
        }
        
        for future in concurrent.futures.as_completed(future_to_file):
            result = future.result()
            results.append(result)
    
    # Log summary
    archived_count = len([r for r in results if r['status'] == 'archived'])
    total_size = sum(r.get('size', 0) for r in results if r['status'] == 'archived')
    
    print(f"Archival complete. Files archived: {archived_count}, "
          f"Total size: {total_size / (1024**3):.2f} GB")
    
    return results


def archive_single_file(
    bucket_name: str,
    file_info: Dict,
    archive_prefix: str,
    delete_after_archive: bool
) -> Dict:
    """
    Archive a single file.
    """
    key = file_info['key']
    
    try:
        # Generate archive key
        archive_key = f"{archive_prefix}{key}"
        
        # Copy object with new storage class
        copy_source = {'Bucket': bucket_name, 'Key': key}
        
        # Get object metadata
        response = s3_client.head_object(Bucket=bucket_name, Key=key)
        metadata = response.get('Metadata', {})
        content_type = response.get('ContentType', 'application/octet-stream')
        
        # Copy to archive location with GLACIER storage class
        s3_client.copy_object(
            CopySource=copy_source,
            Bucket=bucket_name,
            Key=archive_key,
            StorageClass='GLACIER',
            MetadataDirective='REPLACE',
            Metadata={
                **metadata,
                'archived-from': key,
                'archived-date': datetime.utcnow().isoformat(),
                'original-storage-class': file_info['storage_class']
            },
            ContentType=content_type
        )
        
        # Tag original file as archived
        if TAG_ARCHIVED:
            s3_client.put_object_tagging(
                Bucket=bucket_name,
                Key=key,
                Tagging={
                    'TagSet': [
                        {'Key': 'archived', 'Value': 'true'},
                        {'Key': 'archive-location', 'Value': archive_key},
                        {'Key': 'archive-date', 'Value': datetime.utcnow().isoformat()}
                    ]
                }
            )
        
        # Delete original if requested
        if delete_after_archive:
            s3_client.delete_object(Bucket=bucket_name, Key=key)
            action = 'moved'
        else:
            # Change storage class of original to save costs
            s3_client.copy_object(
                CopySource=copy_source,
                Bucket=bucket_name,
                Key=key,
                StorageClass='GLACIER',
                MetadataDirective='COPY'
            )
            action = 'archived'
        
        return {
            'key': key,
            'archive_key': archive_key,
            'status': 'archived',
            'action': action,
            'size': file_info['size'],
            'last_modified': file_info['last_modified'].isoformat(),
            'original_storage_class': file_info['storage_class']
        }
        
    except Exception as e:
        print(f"Error archiving file {key}: {e}")
        return {
            'key': key,
            'status': 'error',
            'error': str(e)
        }


def get_archive_candidates(
    bucket_name: str,
    cutoff_date: datetime
) -> List[Dict]:
    """
    Get list of files that are candidates for archival.
    """
    candidates = []
    total_size = 0
    
    paginator = s3_client.get_paginator('list_objects_v2')
    
    for page in paginator.paginate(Bucket=bucket_name):
        if 'Contents' not in page:
            continue
        
        for obj in page['Contents']:
            last_modified = obj['LastModified'].replace(tzinfo=None)
            
            if last_modified < cutoff_date:
                storage_class = obj.get('StorageClass', 'STANDARD')
                
                if storage_class in ['STANDARD', 'STANDARD_IA']:
                    candidates.append({
                        'key': obj['Key'],
                        'size': obj['Size'],
                        'last_modified': last_modified,
                        'storage_class': storage_class,
                        'age_days': (datetime.utcnow() - last_modified).days
                    })
                    total_size += obj['Size']
    
    return {
        'candidates': candidates,
        'total_count': len(candidates),
        'total_size_gb': total_size / (1024**3),
        'potential_savings': calculate_archive_savings(candidates)
    }


def calculate_archive_savings(candidates: List[Dict]) -> Dict:
    """
    Calculate potential savings from archiving.
    """
    # S3 pricing per GB per month (simplified)
    pricing = {
        'STANDARD': 0.023,
        'STANDARD_IA': 0.0125,
        'GLACIER': 0.004,
        'DEEP_ARCHIVE': 0.00099
    }
    
    current_cost = 0
    glacier_cost = 0
    
    for file in candidates:
        size_gb = file['size'] / (1024**3)
        current_storage = file['storage_class']
        
        current_cost += size_gb * pricing.get(current_storage, pricing['STANDARD'])
        glacier_cost += size_gb * pricing['GLACIER']
    
    return {
        'current_monthly_cost': current_cost,
        'glacier_monthly_cost': glacier_cost,
        'monthly_savings': current_cost - glacier_cost,
        'annual_savings': (current_cost - glacier_cost) * 12
    }