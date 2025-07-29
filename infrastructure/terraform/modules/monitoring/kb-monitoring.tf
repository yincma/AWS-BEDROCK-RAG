# Knowledge Base monitoring configuration

# Knowledge Base sync failure alarm
resource "aws_cloudwatch_metric_alarm" "kb_sync_failures" {
  count = var.enable_kb_sync_monitoring ? 1 : 0

  alarm_name          = "${var.project_name}-kb-sync-failures-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "Document processor Lambda errors (KB sync failures)"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = "${var.project_name}-document-processor-${var.environment}"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# S3 event processing failure alarm
resource "aws_cloudwatch_metric_alarm" "s3_event_processing_failures" {
  count = var.enable_kb_sync_monitoring ? 1 : 0

  alarm_name          = "${var.project_name}-s3-event-failures-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "2"
  alarm_description   = "S3 event processing failures in document processor"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = "${var.project_name}-document-processor-${var.environment}"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# Custom CloudWatch log metric filter - KB sync failures
resource "aws_cloudwatch_log_metric_filter" "kb_sync_failures" {
  count = var.enable_kb_sync_monitoring ? 1 : 0

  name           = "${var.project_name}-kb-sync-failures-${var.environment}"
  log_group_name = "/aws/lambda/${var.project_name}-document-processor-${var.environment}"

  pattern = "[time, request_id, level=ERROR, message, ... msg=\"Failed to start Knowledge Base sync*\"]"

  metric_transformation {
    name      = "KBSyncFailures"
    namespace = "${var.project_name}/KnowledgeBase"
    value     = "1"
    default_value = "0"
  }
}

# Custom CloudWatch log metric filter - KB sync success
resource "aws_cloudwatch_log_metric_filter" "kb_sync_success" {
  count = var.enable_kb_sync_monitoring ? 1 : 0

  name           = "${var.project_name}-kb-sync-success-${var.environment}"
  log_group_name = "/aws/lambda/${var.project_name}-document-processor-${var.environment}"

  pattern = "[time, request_id, level=INFO, message, ... msg=\"Knowledge Base sync task started*\"]"

  metric_transformation {
    name      = "KBSyncSuccess"
    namespace = "${var.project_name}/KnowledgeBase"
    value     = "1"
    default_value = "0"
  }
}

# Custom metric based alarm - KB sync failure rate
resource "aws_cloudwatch_metric_alarm" "kb_sync_failure_rate" {
  count = var.enable_kb_sync_monitoring ? 1 : 0

  alarm_name          = "${var.project_name}-kb-sync-failure-rate-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  threshold           = "0.1"  # 10% failure rate
  alarm_description   = "Knowledge Base sync failure rate above 10%"
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "failure_rate"
    expression  = "failures / (failures + successes)"
    label       = "Failure Rate"
    return_data = true
  }

  metric_query {
    id = "failures"
    metric {
      metric_name = "KBSyncFailures"
      namespace   = "${var.project_name}/KnowledgeBase"
      period      = "300"
      stat        = "Sum"
    }
  }

  metric_query {
    id = "successes"
    metric {
      metric_name = "KBSyncSuccess"
      namespace   = "${var.project_name}/KnowledgeBase"
      period      = "300"
      stat        = "Sum"
    }
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# CloudWatch Dashboard Widget for KB Monitoring
resource "aws_cloudwatch_dashboard" "kb_monitoring" {
  count = var.enable_kb_sync_monitoring ? 1 : 0

  dashboard_name = "${var.project_name}-kb-monitoring-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["${var.project_name}/KnowledgeBase", "KBSyncSuccess", { stat = "Sum", label = "Sync Success" }],
            [".", "KBSyncFailures", { stat = "Sum", label = "Sync Failures", color = "#d62728" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Knowledge Base Sync Status"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", "${var.project_name}-document-processor-${var.environment}", { stat = "Average", label = "Average Processing Time" }],
            [".", ".", ".", ".", { stat = "Maximum", label = "Maximum Processing Time", color = "#ff7f0e" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Document Processing Performance"
          period  = 300
          yAxis = {
            left = { 
              min = 0
              label = "milliseconds"
            }
          }
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6

        properties = {
          query   = "SOURCE '/aws/lambda/${var.project_name}-document-processor-${var.environment}' | fields @timestamp, @message | filter @message like /Knowledge Base/ | sort @timestamp desc | limit 100"
          region  = data.aws_region.current.name
          title   = "Knowledge Base Sync Logs"
        }
      }
    ]
  })
}

# Data source - get current region
data "aws_region" "current" {}