# Lambda Performance Configuration for PERF-001
# Enhanced performance optimization settings for all Lambda functions

locals {
  # Environment-specific performance multipliers
  performance_multipliers = {
    dev = {
      memory_multiplier      = 0.5 # Lower memory in dev
      concurrency_multiplier = 0.2 # Lower concurrency in dev
      warmup_frequency       = 15  # Less frequent warmup in dev (minutes)
    }
    staging = {
      memory_multiplier      = 0.8 # Moderate memory in staging
      concurrency_multiplier = 0.5 # Moderate concurrency in staging
      warmup_frequency       = 10  # Moderate warmup frequency
    }
    prod = {
      memory_multiplier      = 1.0 # Full memory in prod
      concurrency_multiplier = 1.0 # Full concurrency in prod
      warmup_frequency       = 5   # Aggressive warmup in prod
    }
  }

  # Function-specific optimization profiles
  optimization_profiles = {
    # Query Handler - Latency sensitive
    query_handler = {
      base_memory                  = 1536  # Optimal for Python + AI workloads
      base_timeout                 = 30    # Quick response expected
      base_reserved_concurrency    = 50    # High concurrent users
      base_provisioned_concurrency = 10    # Always warm instances
      enable_snap_start            = false # Not applicable for Python
      enable_graviton2             = true  # Better price/performance
      function_type                = "api_handler"
      enable_auto_scaling          = true
      cold_start_priority          = "high"
    }

    # Document Processor - Compute intensive
    document_processor = {
      base_memory                  = 3008 # High memory for document processing
      base_timeout                 = 900  # Long running tasks
      base_reserved_concurrency    = 10   # Lower concurrency needs
      base_provisioned_concurrency = 2    # Minimal warm instances
      enable_snap_start            = false
      enable_graviton2             = true
      function_type                = "data_processor"
      enable_auto_scaling          = false # Batch processing doesn't need auto-scaling
      cold_start_priority          = "medium"
    }

    # Authorizer - Ultra low latency
    authorizer = {
      base_memory                  = 512 # Lightweight function
      base_timeout                 = 10  # Must be fast
      base_reserved_concurrency    = 100 # High concurrent auth requests
      base_provisioned_concurrency = 20  # Many warm instances
      enable_snap_start            = false
      enable_graviton2             = true
      function_type                = "api_handler"
      enable_auto_scaling          = true
      cold_start_priority          = "critical" # Auth must never be slow
    }

    # Index Creator - Batch processing
    index_creator = {
      base_memory                  = 1024 # Moderate memory needs
      base_timeout                 = 300  # Medium duration
      base_reserved_concurrency    = 5    # Low concurrency
      base_provisioned_concurrency = 1    # Minimal warm instances
      enable_snap_start            = false
      enable_graviton2             = true
      function_type                = "batch_processor"
      enable_auto_scaling          = false
      cold_start_priority          = "low"
    }
  }

  # Calculate environment-adjusted values
  env_multiplier = local.performance_multipliers[var.environment]

  optimized_functions = {
    for name, profile in local.optimization_profiles : name => {
      memory_size = ceil(profile.base_memory * local.env_multiplier.memory_multiplier)
      timeout     = profile.base_timeout
      reserved_concurrent_executions = ceil(
        profile.base_reserved_concurrency * local.env_multiplier.concurrency_multiplier
      )
      provisioned_concurrent_executions = var.enable_provisioned_concurrency ? ceil(
        profile.base_provisioned_concurrency * local.env_multiplier.concurrency_multiplier
      ) : 0
      enable_snap_start   = profile.enable_snap_start
      enable_graviton2    = profile.enable_graviton2
      function_type       = profile.function_type
      enable_auto_scaling = profile.enable_auto_scaling && var.environment == "prod"
      cold_start_priority = profile.cold_start_priority
    }
  }

  # CloudWatch Insights queries for performance analysis
  performance_queries = {
    cold_starts = <<-EOQ
      fields @timestamp, @initDuration as coldStartMs, @duration as executionMs
      | filter @type = "REPORT" and @initDuration > 0
      | stats count() as coldStarts,
              avg(coldStartMs) as avgColdStartMs,
              max(coldStartMs) as maxColdStartMs,
              pct(coldStartMs, 95) as p95ColdStartMs
    EOQ

    memory_utilization = <<-EOQ
      fields @timestamp, @maxMemoryUsed/@memorySize * 100 as memoryUtilPct
      | filter @type = "REPORT"
      | stats avg(memoryUtilPct) as avgMemoryUtil,
              max(memoryUtilPct) as maxMemoryUtil,
              pct(memoryUtilPct, 95) as p95MemoryUtil
    EOQ

    performance_metrics = <<-EOQ
      fields @timestamp, @duration, @billedDuration, @maxMemoryUsed
      | filter @type = "REPORT"
      | stats count() as invocations,
              avg(@duration) as avgDuration,
              max(@duration) as maxDuration,
              pct(@duration, 50) as p50Duration,
              pct(@duration, 95) as p95Duration,
              pct(@duration, 99) as p99Duration
    EOQ
  }
}

# Performance monitoring dashboard configuration
resource "aws_cloudwatch_dashboard" "lambda_performance" {
  dashboard_name = "${var.project_name}-lambda-performance-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      # Cold Start Metrics
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          metrics = [
            for fn_name, _ in local.optimized_functions : [
              "AWS/Lambda",
              "InitDuration",
              "FunctionName",
              "${var.project_name}-${fn_name}-${var.environment}",
              { stat = "Average", label = "${fn_name} Avg" }
            ]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Lambda Cold Start Duration"
          yAxis = {
            left = {
              showUnits = false
              label     = "Duration (ms)"
            }
          }
        }
      },

      # Memory Utilization
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          metrics = [
            for fn_name, config in local.optimized_functions : [
              "LambdaInsights",
              "memory_utilization",
              "function_name",
              "${var.project_name}-${fn_name}-${var.environment}",
              { stat = "Average", label = "${fn_name} (${config.memory_size}MB)" }
            ]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Lambda Memory Utilization"
          yAxis = {
            left = {
              showUnits = false
              label     = "Utilization %"
              min       = 0
              max       = 100
            }
          }
        }
      },

      # Function Duration
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          metrics = concat(
            # P50 (median)
            [for fn_name, _ in local.optimized_functions : [
              "AWS/Lambda",
              "Duration",
              "FunctionName",
              "${var.project_name}-${fn_name}-${var.environment}",
              { stat = "p50", label = "${fn_name} p50" }
            ]],
            # P95
            [for fn_name, _ in local.optimized_functions : [
              "AWS/Lambda",
              "Duration",
              "FunctionName",
              "${var.project_name}-${fn_name}-${var.environment}",
              { stat = "p95", label = "${fn_name} p95" }
            ]],
            # P99
            [for fn_name, _ in local.optimized_functions : [
              "AWS/Lambda",
              "Duration",
              "FunctionName",
              "${var.project_name}-${fn_name}-${var.environment}",
              { stat = "p99", label = "${fn_name} p99" }
            ]]
          )
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Lambda Execution Duration Percentiles"
          yAxis = {
            left = {
              showUnits = false
              label     = "Duration (ms)"
            }
          }
        }
      },

      # Concurrent Executions
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          metrics = [
            for fn_name, config in local.optimized_functions : [
              "AWS/Lambda",
              "ConcurrentExecutions",
              "FunctionName",
              "${var.project_name}-${fn_name}-${var.environment}",
              {
                stat  = "Maximum",
                label = "${fn_name} (Reserved: ${config.reserved_concurrent_executions})"
              }
            ]
          ]
          period = 60
          stat   = "Maximum"
          region = var.aws_region
          title  = "Lambda Concurrent Executions"
          yAxis = {
            left = {
              showUnits = false
              label     = "Concurrent Executions"
            }
          }
        }
      }
    ]
  })
}

# Outputs for performance configuration
output "optimized_function_configs" {
  description = "Optimized configuration for each Lambda function"
  value       = local.optimized_functions
}

output "performance_dashboard_url" {
  description = "URL to the Lambda performance dashboard"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.lambda_performance.dashboard_name}"
}