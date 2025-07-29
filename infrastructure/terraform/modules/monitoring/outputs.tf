# 监控模块输出

output "alerts_topic_arn" {
  description = "告警SNS主题ARN"
  value       = aws_sns_topic.alerts.arn
}

output "dashboard_url" {
  description = "CloudWatch Dashboard URL"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "alarm_arns" {
  description = "所有告警的ARN"
  value = merge(
    {
      api_high_error_rate = aws_cloudwatch_metric_alarm.api_high_error_rate.arn
      api_high_latency    = aws_cloudwatch_metric_alarm.api_high_latency.arn
    },
    {
      for k, v in aws_cloudwatch_metric_alarm.lambda_errors :
      "${k}_errors" => v.arn
    },
    {
      for k, v in aws_cloudwatch_metric_alarm.lambda_duration :
      "${k}_duration" => v.arn
    },
    var.cost_alert_threshold > 0 ? {
      cost_alert = aws_cloudwatch_metric_alarm.cost_alert[0].arn
    } : {}
  )
}

output "log_metric_filters" {
  description = "日志指标过滤器"
  value = {
    bedrock_requests = aws_cloudwatch_log_metric_filter.bedrock_requests.name
    bedrock_errors   = aws_cloudwatch_log_metric_filter.bedrock_errors.name
    cold_starts = {
      for k, v in aws_cloudwatch_log_metric_filter.cold_starts :
      k => v.name
    }
  }
}

output "xray_sampling_rule_arn" {
  description = "X-Ray采样规则ARN"
  value       = var.enable_xray_tracing ? aws_xray_sampling_rule.main[0].arn : null
}

output "synthetics_canary_name" {
  description = "Synthetics Canary名称"
  value       = var.enable_synthetics ? aws_synthetics_canary.api_monitor[0].name : null
}