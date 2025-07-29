# Lambda Warm-up Configuration for Cold Start Reduction
# Part of PERF-001 implementation

# EventBridge Rules for Lambda Warm-up
resource "aws_cloudwatch_event_rule" "lambda_warmup" {
  for_each = {
    for name, config in local.optimized_functions :
    name => config if config.cold_start_priority != "low" && var.enable_cold_start_optimization && lookup(var.lambda_function_arns, name, "") != ""
  }

  name                = "${var.project_name}-${each.key}-warmup-${var.environment}"
  description         = "Warm-up schedule for ${each.key} Lambda function"
  schedule_expression = "rate(${local.performance_multipliers[var.environment].warmup_frequency} minutes)"

  tags = merge(
    var.common_tags,
    {
      Purpose  = "Lambda-Warmup"
      Function = each.key
    }
  )
}

# EventBridge Targets for Lambda Warm-up
resource "aws_cloudwatch_event_target" "lambda_warmup" {
  for_each = {
    for name, config in local.optimized_functions :
    name => config if config.cold_start_priority != "low" && var.enable_cold_start_optimization && lookup(var.lambda_function_arns, name, "") != ""
  }

  rule      = aws_cloudwatch_event_rule.lambda_warmup[each.key].name
  target_id = "WarmupTarget_${each.key}"
  arn       = var.lambda_function_arns[each.key]

  # Warm-up payload
  input = jsonencode({
    __warmup  = true
    timestamp = "$${timestamp}"
    function  = each.key
    priority  = each.value.cold_start_priority
  })
}

# Lambda permissions for EventBridge
resource "aws_lambda_permission" "allow_eventbridge_warmup" {
  for_each = {
    for name, config in local.optimized_functions :
    name => config if config.cold_start_priority != "low" && var.enable_cold_start_optimization && lookup(var.lambda_function_names, name, "") != ""
  }

  statement_id  = "AllowExecutionFromEventBridgeWarmup"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_names[each.key]
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lambda_warmup[each.key].arn
}

# Lambda function for intelligent warm-up orchestration
resource "aws_lambda_function" "warmup_orchestrator" {
  count = var.enable_intelligent_warmup ? 1 : 0

  function_name = "${var.project_name}-${var.function_name}-warmup-${var.environment}"
  description   = "Intelligent warm-up orchestrator for Lambda functions"

  runtime       = "python3.11"
  handler       = "index.lambda_handler"
  memory_size   = 256
  timeout       = 60
  architectures = ["arm64"]

  role = aws_iam_role.warmup_orchestrator[0].arn

  environment {
    variables = {
      ENVIRONMENT = var.environment
      FUNCTIONS = jsonencode({
        for name, config in local.optimized_functions :
        name => {
          arn                     = lookup(var.lambda_function_arns, name, "")
          priority                = config.cold_start_priority
          provisioned_concurrency = config.provisioned_concurrent_executions
          reserved_concurrency    = config.reserved_concurrent_executions
        } if lookup(var.lambda_function_arns, name, "") != ""
      })
    }
  }

  # Inline code for the orchestrator
  filename         = data.archive_file.warmup_orchestrator[0].output_path
  source_code_hash = data.archive_file.warmup_orchestrator[0].output_base64sha256

  tags = merge(
    var.common_tags,
    {
      Purpose = "Warmup-Orchestrator"
    }
  )
}

# Orchestrator code
locals {
  warmup_orchestrator_code = <<-EOT
import json
import boto3
import os
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime

lambda_client = boto3.client('lambda')
cloudwatch_client = boto3.client('cloudwatch')

def lambda_handler(event, context):
    """Intelligent warm-up orchestrator"""
    functions = json.loads(os.environ['FUNCTIONS'])
    environment = os.environ['ENVIRONMENT']
    
    results = {}
    
    # Group functions by priority
    priority_groups = {
        'critical': [],
        'high': [],
        'medium': []
    }
    
    for name, config in functions.items():
        priority = config.get('priority', 'medium')
        priority_groups[priority].append((name, config))
    
    # Warm up functions in priority order
    with ThreadPoolExecutor(max_workers=10) as executor:
        futures = []
        
        # Critical priority first
        for name, config in priority_groups['critical']:
            future = executor.submit(warm_up_function, name, config, concurrent_calls=5)
            futures.append((name, future))
        
        # High priority
        for name, config in priority_groups['high']:
            future = executor.submit(warm_up_function, name, config, concurrent_calls=3)
            futures.append((name, future))
        
        # Medium priority
        for name, config in priority_groups['medium']:
            future = executor.submit(warm_up_function, name, config, concurrent_calls=1)
            futures.append((name, future))
        
        # Collect results
        for name, future in futures:
            try:
                results[name] = future.result()
            except Exception as e:
                results[name] = {'error': str(e)}
    
    # Report metrics
    report_warmup_metrics(results)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Warm-up completed',
            'results': results,
            'timestamp': datetime.utcnow().isoformat()
        })
    }

def warm_up_function(function_name, config, concurrent_calls=1):
    """Warm up a single function with multiple concurrent calls"""
    arn = config['arn']
    
    with ThreadPoolExecutor(max_workers=concurrent_calls) as executor:
        futures = []
        for i in range(concurrent_calls):
            future = executor.submit(invoke_function, arn, i)
            futures.append(future)
        
        results = []
        for future in as_completed(futures):
            try:
                result = future.result()
                results.append(result)
            except Exception as e:
                results.append({'error': str(e)})
    
    return {
        'function': function_name,
        'concurrent_calls': concurrent_calls,
        'results': results
    }

def invoke_function(function_arn, call_index):
    """Invoke a Lambda function for warm-up"""
    try:
        response = lambda_client.invoke(
            FunctionName=function_arn,
            InvocationType='RequestResponse',
            Payload=json.dumps({
                '__warmup': True,
                'call_index': call_index,
                'timestamp': datetime.utcnow().isoformat()
            })
        )
        
        return {
            'status_code': response['StatusCode'],
            'cold_start': response.get('ResponseMetadata', {}).get('HTTPHeaders', {}).get('x-amz-executed-version', '') == '$LATEST'
        }
    except Exception as e:
        return {'error': str(e)}

def report_warmup_metrics(results):
    """Report warm-up metrics to CloudWatch"""
    try:
        metrics = []
        
        for function_name, result in results.items():
            if 'error' not in result:
                successful_warmups = sum(1 for r in result.get('results', []) if 'error' not in r)
                cold_starts = sum(1 for r in result.get('results', []) if r.get('cold_start', False))
                
                metrics.extend([
                    {
                        'MetricName': 'WarmupSuccess',
                        'Value': successful_warmups,
                        'Unit': 'Count',
                        'Dimensions': [
                            {'Name': 'FunctionName', 'Value': function_name},
                            {'Name': 'Environment', 'Value': os.environ['ENVIRONMENT']}
                        ]
                    },
                    {
                        'MetricName': 'WarmupColdStarts',
                        'Value': cold_starts,
                        'Unit': 'Count',
                        'Dimensions': [
                            {'Name': 'FunctionName', 'Value': function_name},
                            {'Name': 'Environment', 'Value': os.environ['ENVIRONMENT']}
                        ]
                    }
                ])
        
        if metrics:
            cloudwatch_client.put_metric_data(
                Namespace='LambdaWarmup',
                MetricData=metrics
            )
    except Exception as e:
        print(f"Error reporting metrics: {e}")
EOT
}

# Create deployment package for orchestrator
data "archive_file" "warmup_orchestrator" {
  count = var.enable_intelligent_warmup ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/warmup-orchestrator.zip"

  source {
    content  = local.warmup_orchestrator_code
    filename = "index.py"
  }
}

# IAM role for orchestrator
resource "aws_iam_role" "warmup_orchestrator" {
  count = var.enable_intelligent_warmup ? 1 : 0

  name = "${var.project_name}-${var.function_name}-warmup-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags
}

# IAM policy for orchestrator
resource "aws_iam_role_policy" "warmup_orchestrator" {
  count = var.enable_intelligent_warmup ? 1 : 0

  name = "warmup-orchestrator-policy"
  role = aws_iam_role.warmup_orchestrator[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      # Only add lambda invoke permissions if there are functions to invoke
      length([
        for name, _ in local.optimized_functions :
        lookup(var.lambda_function_arns, name, "")
        if lookup(var.lambda_function_arns, name, "") != ""
        ]) > 0 ? [
        {
          Effect = "Allow"
          Action = [
            "lambda:InvokeFunction",
            "lambda:GetFunctionConfiguration"
          ]
          Resource = [
            for name, _ in local.optimized_functions :
            lookup(var.lambda_function_arns, name, "")
            if lookup(var.lambda_function_arns, name, "") != ""
          ]
        }
      ] : [],
      # Always include these permissions
      [
        {
          Effect = "Allow"
          Action = [
            "cloudwatch:PutMetricData"
          ]
          Resource = "*"
        },
        {
          Effect = "Allow"
          Action = [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ]
          Resource = "arn:aws:logs:${var.aws_region}:*:*"
        }
      ]
    )
  })
}

# Basic Lambda execution policy attachment
resource "aws_iam_role_policy_attachment" "warmup_orchestrator_basic" {
  count = var.enable_intelligent_warmup ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.warmup_orchestrator[0].name
}

# EventBridge rule for orchestrator
resource "aws_cloudwatch_event_rule" "warmup_orchestrator" {
  count = var.enable_intelligent_warmup ? 1 : 0

  name                = "${var.project_name}-warmup-orchestrator-${var.environment}"
  description         = "Trigger intelligent warm-up orchestrator"
  schedule_expression = "rate(${local.performance_multipliers[var.environment].warmup_frequency} minutes)"

  tags = merge(
    var.common_tags,
    {
      Purpose = "Warmup-Orchestrator-Trigger"
    }
  )
}

# EventBridge target for orchestrator
resource "aws_cloudwatch_event_target" "warmup_orchestrator" {
  count = var.enable_intelligent_warmup ? 1 : 0

  rule      = aws_cloudwatch_event_rule.warmup_orchestrator[0].name
  target_id = "OrchestratorTarget_${var.function_name}"
  arn       = aws_lambda_function.warmup_orchestrator[0].arn
}

# Permission for EventBridge to invoke orchestrator
resource "aws_lambda_permission" "allow_eventbridge_orchestrator" {
  count = var.enable_intelligent_warmup ? 1 : 0

  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.warmup_orchestrator[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.warmup_orchestrator[0].arn
}

# CloudWatch alarms for warm-up effectiveness
resource "aws_cloudwatch_metric_alarm" "warmup_effectiveness" {
  for_each = {
    for name, config in local.optimized_functions :
    name => config if config.cold_start_priority != "low" && var.enable_cold_start_optimization && lookup(var.lambda_function_names, name, "") != ""
  }

  alarm_name          = "${var.project_name}-${each.key}-warmup-effectiveness-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "WarmupColdStarts"
  namespace           = "LambdaWarmup"
  period              = "300"
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Warm-up not effective for ${each.key}"

  dimensions = {
    FunctionName = each.key
    Environment  = var.environment
  }

  alarm_actions = var.alarm_sns_topic_arns

  tags = var.common_tags
}