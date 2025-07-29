# Lambda Auto-scaling Configuration
# Part of PERF-001: Dynamic scaling for provisioned concurrency

# Application Auto Scaling targets for provisioned concurrency
resource "aws_appautoscaling_target" "lambda_concurrency" {
  for_each = {
    for name, config in local.optimized_functions :
    name => config if config.enable_auto_scaling && config.provisioned_concurrent_executions > 0
  }

  max_capacity       = ceil(each.value.provisioned_concurrent_executions * 3)            # 3x peak capacity
  min_capacity       = max(1, floor(each.value.provisioned_concurrent_executions * 0.5)) # 50% minimum
  resource_id        = "function:${var.lambda_function_names[each.key]}:provisioned-concurrency:${var.lambda_function_aliases[each.key]}"
  scalable_dimension = "lambda:function:ProvisionedConcurrency"
  service_namespace  = "lambda"

  depends_on = [var.lambda_provisioned_concurrency_configs]
}

# Target tracking scaling policy based on utilization
resource "aws_appautoscaling_policy" "lambda_target_tracking" {
  for_each = {
    for name, config in local.optimized_functions :
    name => config if config.enable_auto_scaling && config.provisioned_concurrent_executions > 0
  }

  name               = "${var.project_name}-${each.key}-target-tracking-${var.environment}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.lambda_concurrency[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.lambda_concurrency[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.lambda_concurrency[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = var.target_utilization_percentage

    predefined_metric_specification {
      predefined_metric_type = "LambdaProvisionedConcurrencyUtilization"
    }

    scale_in_cooldown  = var.scale_in_cooldown_seconds
    scale_out_cooldown = var.scale_out_cooldown_seconds
  }
}

# Scheduled scaling for predictable workloads
resource "aws_appautoscaling_scheduled_action" "scale_up_business_hours" {
  for_each = {
    for name, config in local.optimized_functions :
    name => config if config.enable_auto_scaling &&
    config.provisioned_concurrent_executions > 0 &&
    var.enable_scheduled_scaling
  }

  name               = "${var.project_name}-${each.key}-scale-up-business-${var.environment}"
  service_namespace  = aws_appautoscaling_target.lambda_concurrency[each.key].service_namespace
  resource_id        = aws_appautoscaling_target.lambda_concurrency[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.lambda_concurrency[each.key].scalable_dimension

  # Scale up at 8 AM local time (converted to UTC)
  schedule = "cron(0 ${8 + var.utc_offset} ? * MON-FRI *)"

  scalable_target_action {
    min_capacity = each.value.provisioned_concurrent_executions
    max_capacity = ceil(each.value.provisioned_concurrent_executions * 2.5)
  }
}

resource "aws_appautoscaling_scheduled_action" "scale_down_after_hours" {
  for_each = {
    for name, config in local.optimized_functions :
    name => config if config.enable_auto_scaling &&
    config.provisioned_concurrent_executions > 0 &&
    var.enable_scheduled_scaling
  }

  name               = "${var.project_name}-${each.key}-scale-down-after-${var.environment}"
  service_namespace  = aws_appautoscaling_target.lambda_concurrency[each.key].service_namespace
  resource_id        = aws_appautoscaling_target.lambda_concurrency[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.lambda_concurrency[each.key].scalable_dimension

  # Scale down at 7 PM local time (converted to UTC)
  schedule = "cron(0 ${19 + var.utc_offset} ? * MON-FRI *)"

  scalable_target_action {
    min_capacity = max(1, floor(each.value.provisioned_concurrent_executions * 0.3))
    max_capacity = each.value.provisioned_concurrent_executions
  }
}

# Weekend scaling (minimal capacity)
resource "aws_appautoscaling_scheduled_action" "scale_down_weekend" {
  for_each = {
    for name, config in local.optimized_functions :
    name => config if config.enable_auto_scaling &&
    config.provisioned_concurrent_executions > 0 &&
    var.enable_scheduled_scaling &&
    config.cold_start_priority != "critical"
  }

  name               = "${var.project_name}-${each.key}-scale-down-weekend-${var.environment}"
  service_namespace  = aws_appautoscaling_target.lambda_concurrency[each.key].service_namespace
  resource_id        = aws_appautoscaling_target.lambda_concurrency[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.lambda_concurrency[each.key].scalable_dimension

  # Scale down on Saturday morning
  schedule = "cron(0 ${1 + var.utc_offset} ? * SAT *)"

  scalable_target_action {
    min_capacity = 1
    max_capacity = max(2, floor(each.value.provisioned_concurrent_executions * 0.2))
  }
}

# Step scaling policy for rapid scale-out during traffic spikes
resource "aws_appautoscaling_policy" "lambda_step_scaling" {
  for_each = {
    for name, config in local.optimized_functions :
    name => config if config.enable_auto_scaling &&
    config.provisioned_concurrent_executions > 0 &&
    config.cold_start_priority == "critical"
  }

  name               = "${var.project_name}-${each.key}-step-scaling-${var.environment}"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.lambda_concurrency[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.lambda_concurrency[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.lambda_concurrency[each.key].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "PercentChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Average"

    # Scale out aggressively when utilization is high
    step_adjustment {
      metric_interval_lower_bound = 70
      metric_interval_upper_bound = 85
      scaling_adjustment          = 50 # Increase by 50%
    }

    step_adjustment {
      metric_interval_lower_bound = 85
      metric_interval_upper_bound = 95
      scaling_adjustment          = 100 # Double capacity
    }

    step_adjustment {
      metric_interval_lower_bound = 95
      scaling_adjustment          = 150 # 2.5x capacity for extreme load
    }
  }
}

# CloudWatch metric alarm for triggering step scaling
resource "aws_cloudwatch_metric_alarm" "high_utilization" {
  for_each = {
    for name, config in local.optimized_functions :
    name => config if config.enable_auto_scaling &&
    config.provisioned_concurrent_executions > 0 &&
    config.cold_start_priority == "critical"
  }

  alarm_name          = "${var.project_name}-${each.key}-high-util-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ProvisionedConcurrencyUtilization"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Average"
  threshold           = "70"
  alarm_description   = "Triggers step scaling for ${each.key}"

  dimensions = {
    FunctionName = var.lambda_function_names[each.key]
    Resource     = "${var.lambda_function_names[each.key]}:${var.lambda_function_aliases[each.key]}"
  }

  alarm_actions = [aws_appautoscaling_policy.lambda_step_scaling[each.key].arn]

  tags = var.common_tags
}

# Custom CloudWatch metrics for scaling decisions
resource "aws_cloudwatch_log_metric_filter" "cold_start_rate" {
  for_each = {
    for name, config in local.optimized_functions :
    name => config if var.enable_cold_start_optimization
  }

  name           = "${var.project_name}-${each.key}-cold-start-rate-${var.environment}"
  log_group_name = "/aws/lambda/${var.lambda_function_names[each.key]}"
  pattern        = "[report_label=\"REPORT\", ..., init_duration > 0]"

  metric_transformation {
    name      = "ColdStartRate"
    namespace = "Lambda/Performance"
    value     = "1"
    dimensions = {
      FunctionName = var.lambda_function_names[each.key]
      Environment  = var.environment
    }
  }
}

# Dashboard for auto-scaling monitoring
resource "aws_cloudwatch_dashboard" "autoscaling_monitor" {
  count = var.enable_autoscaling_dashboard ? 1 : 0

  dashboard_name = "${var.project_name}-lambda-autoscaling-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 24
        height = 8
        properties = {
          metrics = concat(
            # Provisioned concurrency
            [for name, config in local.optimized_functions : [
              "AWS/Lambda",
              "ProvisionedConcurrentExecutions",
              "FunctionName",
              var.lambda_function_names[name],
              "Resource",
              "${var.lambda_function_names[name]}:${var.lambda_function_aliases[name]}",
              { stat = "Average", label = "${name} Provisioned" }
            ] if config.enable_auto_scaling],
            # Utilization
            [for name, config in local.optimized_functions : [
              "AWS/Lambda",
              "ProvisionedConcurrencyUtilization",
              "FunctionName",
              var.lambda_function_names[name],
              "Resource",
              "${var.lambda_function_names[name]}:${var.lambda_function_aliases[name]}",
              { stat = "Average", label = "${name} Utilization %" }
            ] if config.enable_auto_scaling]
          )
          period = 60
          stat   = "Average"
          region = var.aws_region
          title  = "Lambda Auto-scaling Overview"
          yAxis = {
            left = {
              showUnits = false
              label     = "Count / Percentage"
            }
          }
          annotations = {
            horizontal = [
              {
                label = "Target Utilization"
                value = var.target_utilization_percentage
              }
            ]
          }
        }
      }
    ]
  })
}

# Outputs
output "autoscaling_targets" {
  description = "Auto-scaling targets for Lambda functions"
  value = {
    for name, target in aws_appautoscaling_target.lambda_concurrency :
    name => {
      min_capacity = target.min_capacity
      max_capacity = target.max_capacity
      resource_id  = target.resource_id
    }
  }
}

output "autoscaling_dashboard_url" {
  description = "URL to the auto-scaling monitoring dashboard"
  value       = var.enable_autoscaling_dashboard ? "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.autoscaling_monitor[0].dashboard_name}" : null
}