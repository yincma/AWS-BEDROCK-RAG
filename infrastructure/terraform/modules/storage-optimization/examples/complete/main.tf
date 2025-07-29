# Complete example of storage optimization module usage

module "storage_optimization" {
  source = "../../"

  environment  = "prod"
  project_name = "rag-system"

  # S3 buckets optimization configuration
  s3_buckets = {
    # Document storage bucket
    documents = {
      bucket_name                = "rag-system-documents-prod"
      enable_lifecycle           = true
      enable_intelligent_tiering = true
      enable_inventory           = true
      lifecycle_rules = {
        ia_transition_days       = 30   # Move to IA after 30 days
        glacier_transition_days  = 90   # Move to Glacier after 90 days
        deep_archive_days        = 365  # Move to Deep Archive after 1 year
        expiration_days          = 2555 # Delete after 7 years
        log_retention_days       = 90   # Keep logs for 90 days
        enable_multipart_cleanup = true
        enable_version_cleanup   = true
      }
      intelligent_tiering_config = {
        archive_days      = 90
        deep_archive_days = 180
        filter_prefix     = "documents/"
        filter_tags = {
          "AutoArchive" = "true"
        }
      }
    }

    # Application logs bucket
    logs = {
      bucket_name                = "rag-system-logs-prod"
      enable_lifecycle           = true
      enable_intelligent_tiering = false # Not recommended for logs
      enable_inventory           = false
      lifecycle_rules = {
        ia_transition_days      = 7 # Quick transition for logs
        glacier_transition_days = 30
        deep_archive_days       = 90
        expiration_days         = 365 # 1 year retention
        log_retention_days      = 90
      }
    }

    # Backups bucket
    backups = {
      bucket_name                = "rag-system-backups-prod"
      enable_lifecycle           = true
      enable_intelligent_tiering = false
      enable_inventory           = true
      lifecycle_rules = {
        ia_transition_days      = 1   # Immediate transition
        glacier_transition_days = 7   # Quick move to Glacier
        deep_archive_days       = 30  # Archive after 1 month
        expiration_days         = 730 # 2 year retention
      }
    }
  }

  # CloudWatch log groups optimization
  log_groups = {
    "/aws/lambda/rag-query-handler" = {
      retention_in_days  = 90
      enable_compression = true
      enable_sampling    = false # Keep all query logs
    }

    "/aws/lambda/rag-document-processor" = {
      retention_in_days  = 30
      enable_compression = true
      enable_sampling    = true
      sampling_rate      = 0.1 # Sample 10% of logs
    }

    "/aws/apigateway/rag-api" = {
      retention_in_days  = 90
      enable_compression = true
      enable_sampling    = true
      sampling_rate      = 0.05 # Sample 5% of API logs
      subscription_filter = {
        filter_pattern  = "[ERROR]"
        destination_arn = "arn:aws:logs:us-east-1:123456789:destination:error-aggregator"
      }
    }

    "/aws/cognito/userpool/rag-users" = {
      retention_in_days  = 365 # Compliance requirement
      enable_compression = true
      kms_key_id         = "arn:aws:kms:us-east-1:123456789:key/abcd-1234"
    }
  }

  # Compression configuration
  compression_enabled_buckets = {
    documents = {
      bucket_name         = "rag-system-documents-prod"
      compression_types   = ["gzip", "brotli"] # Try both, use best
      file_extensions     = [".json", ".txt", ".csv", ".xml"]
      min_file_size_bytes = 10240           # Only compress files > 10KB
      schedule_expression = "rate(6 hours)" # Run 4 times daily
    }

    logs = {
      bucket_name         = "rag-system-logs-prod"
      compression_types   = ["gzip"] # Logs compress well with gzip
      file_extensions     = [".log", ".json"]
      min_file_size_bytes = 1024 # Compress files > 1KB
      schedule_expression = "rate(1 hour)"
    }
  }

  # Archive configuration
  archive_enabled_buckets = {
    documents = {
      bucket_name          = "rag-system-documents-prod"
      archive_after_days   = 180
      archive_prefix       = "archive/documents/"
      delete_after_archive = false # Keep originals
    }

    logs = {
      bucket_name          = "rag-system-logs-prod"
      archive_after_days   = 30
      archive_prefix       = "archive/logs/"
      delete_after_archive = true # Delete after archiving
    }
  }

  # Cost monitoring configuration
  storage_budget_amount = 500 # $500/month for S3
  logs_budget_amount    = 200 # $200/month for CloudWatch Logs
  alert_email           = "devops@example.com"

  # Advanced configuration
  enable_intelligent_tiering  = true
  enable_inventory            = true
  enable_storage_lens         = true
  enable_metric_filters       = true
  enable_subscription_filters = false # Only for specific log groups

  # Lifecycle transition schedule (production settings)
  lifecycle_transition_schedule = {
    dev = {
      ia_days           = 7
      glacier_days      = 30
      deep_archive_days = 90
      expiration_days   = 180
    }
    staging = {
      ia_days           = 30
      glacier_days      = 90
      deep_archive_days = 180
      expiration_days   = 365
    }
    prod = {
      ia_days           = 90
      glacier_days      = 180
      deep_archive_days = 365
      expiration_days   = 2555 # 7 years
    }
  }

  # Compression settings
  compression_settings = {
    enable_parallel_processing = true
    max_concurrent_executions  = 20
    compression_level          = 9 # Maximum compression
    skip_compressed_files      = true
  }

  # Cost anomaly detection
  cost_anomaly_detection = {
    enabled              = true
    threshold_expression = "ANOMALY_TOTAL_IMPACT_PERCENTAGE > 20"
    frequency            = "DAILY"
  }

  common_tags = {
    Environment        = "prod"
    Project            = "rag-system"
    ManagedBy          = "terraform"
    CostCenter         = "engineering"
    DataClassification = "confidential"
  }
}

# Outputs
output "optimization_summary" {
  description = "Summary of storage optimizations"
  value       = module.storage_optimization.optimization_summary
}

output "monthly_savings_estimate" {
  description = "Estimated monthly savings"
  value       = module.storage_optimization.optimization_summary.total_estimated_savings
}

output "cost_dashboards" {
  description = "Links to cost monitoring dashboards"
  value = {
    cloudwatch   = module.storage_optimization.cost_alerts.dashboard_url
    storage_lens = module.storage_optimization.lifecycle_configurations.storage_lens_dashboard_url
  }
}