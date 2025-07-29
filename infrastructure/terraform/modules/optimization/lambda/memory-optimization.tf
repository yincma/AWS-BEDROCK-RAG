# Lambda Memory Optimization Module
# 基于性能测试和成本分析的内存自动优化配置

# Lambda Power Tuning 配置
resource "aws_lambda_function" "power_tuning" {
  function_name = "lambda-power-tuning"
  description   = "Lambda Power Tuning state machine for optimizing memory settings"
  role          = aws_iam_role.power_tuning.arn
  handler       = "index.handler"
  runtime       = "nodejs18.x"
  timeout       = 300
  memory_size   = 1024

  environment {
    variables = {
      defaultPowerValues = "128,256,512,1024,1536,2048,3008"
      minRAM             = "128"
      maxRAM             = "10240"
    }
  }

  tags = var.tags
}

# Power Tuning IAM Role
resource "aws_iam_role" "power_tuning" {
  name = "lambda-power-tuning-role"

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

  tags = var.tags
}

# Power Tuning IAM Policy
resource "aws_iam_role_policy" "power_tuning" {
  name = "lambda-power-tuning-policy"
  role = aws_iam_role.power_tuning.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction",
          "lambda:GetFunctionConfiguration",
          "lambda:UpdateFunctionConfiguration",
          "lambda:PublishVersion",
          "lambda:PublishLayerVersion"
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
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# 内存优化推荐配置
locals {
  memory_recommendations = {
    # API Handler Functions
    query_handler = {
      base_memory                  = 512
      cpu_intensity                = "medium"
      recommended_memory           = 1024
      cost_optimized_memory        = 768
      performance_optimized_memory = 1536
    }
    document_processor = {
      base_memory                  = 1024
      cpu_intensity                = "high"
      recommended_memory           = 2048
      cost_optimized_memory        = 1536
      performance_optimized_memory = 3008
    }
    authorizer = {
      base_memory                  = 256
      cpu_intensity                = "low"
      recommended_memory           = 512
      cost_optimized_memory        = 384
      performance_optimized_memory = 768
    }
    # Background Processing
    index_creator = {
      base_memory                  = 2048
      cpu_intensity                = "high"
      recommended_memory           = 3008
      cost_optimized_memory        = 2048
      performance_optimized_memory = 4096
    }
  }

  # 基于环境的内存配置策略
  environment_memory_multiplier = {
    dev     = 0.75 # 开发环境使用较少内存
    staging = 1.0  # 预发布环境使用推荐内存
    prod    = 1.25 # 生产环境使用较多内存以确保性能
  }
}

# 动态内存配置
resource "aws_ssm_parameter" "lambda_memory_config" {
  for_each = local.memory_recommendations

  name = "/lambda/${each.key}/memory_config"
  type = "String"
  value = jsonencode({
    base_memory                  = each.value.base_memory
    recommended_memory           = each.value.recommended_memory
    cost_optimized_memory        = each.value.cost_optimized_memory
    performance_optimized_memory = each.value.performance_optimized_memory
    cpu_intensity                = each.value.cpu_intensity
    last_updated                 = timestamp()
  })

  description = "Memory optimization configuration for ${each.key} Lambda function"
  tags        = var.tags
}

# 内存使用监控
resource "aws_cloudwatch_metric_alarm" "memory_utilization" {
  for_each = var.lambda_functions

  alarm_name          = "${each.key}-memory-utilization-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  threshold           = 90
  alarm_description   = "Lambda function ${each.key} memory utilization is high"
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "memory_utilization"
    expression  = "(m1/m2)*100"
    label       = "Memory Utilization %"
    return_data = true
  }

  metric_query {
    id = "m1"
    metric {
      metric_name = "MemoryUtilization"
      namespace   = "AWS/Lambda"
      period      = 300
      stat        = "Maximum"
      dimensions = {
        FunctionName = each.key
      }
    }
  }

  metric_query {
    id = "m2"
    metric {
      metric_name = "MemorySize"
      namespace   = "AWS/Lambda"
      period      = 300
      stat        = "Maximum"
      dimensions = {
        FunctionName = each.key
      }
    }
  }

  alarm_actions = var.alarm_actions
}

# 成本优化分析仪表板
resource "aws_cloudwatch_dashboard" "memory_optimization" {
  dashboard_name = "lambda-memory-optimization"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 24
        height = 8
        properties = {
          metrics = [
            for fn, config in local.memory_recommendations : [
              ["CWAgent", "Lambda_MemoryUtilization", "FunctionName", fn],
              [".", "Lambda_MemorySize", ".", "."]
            ]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Lambda Memory Utilization vs Allocated Memory"
          period  = 300
          yAxis = {
            left = {
              label = "Memory (MB)"
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 8
        width  = 12
        height = 6
        properties = {
          metrics = [
            for fn, config in local.memory_recommendations : [
              ["AWS/Lambda", "Duration", "FunctionName", fn, { stat = "Average" }]
            ]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Average Execution Duration by Function"
          period  = 300
          annotations = {
            horizontal = [
              {
                label = "Target Duration"
                value = 1000
              }
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 8
        width  = 12
        height = 6
        properties = {
          metrics = [
            [{ expression = "SEARCH(' MetricName=\"Invocations\" ', 'Sum', 300)" }],
            [{ expression = "SEARCH(' MetricName=\"Duration\" ', 'Average', 300)" }]
          ]
          view   = "table"
          region = data.aws_region.current.name
          title  = "Lambda Cost Analysis Table"
          period = 300
        }
      }
    ]
  })
}

# 自动调优 Step Functions 状态机
resource "aws_sfn_state_machine" "memory_auto_tuning" {
  name     = "lambda-memory-auto-tuning"
  role_arn = aws_iam_role.step_functions.arn

  definition = jsonencode({
    Comment = "Lambda memory auto-tuning workflow"
    StartAt = "GetFunctionList"
    States = {
      GetFunctionList = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.power_tuning.arn
          Payload = {
            "action" = "list"
          }
        }
        Next = "TuneEachFunction"
      }
      TuneEachFunction = {
        Type           = "Map"
        ItemsPath      = "$.functions"
        MaxConcurrency = 2
        Iterator = {
          StartAt = "TuneFunction"
          States = {
            TuneFunction = {
              Type     = "Task"
              Resource = "arn:aws:states:::lambda:invoke"
              Parameters = {
                FunctionName = aws_lambda_function.power_tuning.arn
                Payload = {
                  "lambdaARN.$"        = "$.functionArn"
                  "powerValues"        = [128, 256, 512, 1024, 1536, 2048, 3008]
                  "num"                = 10
                  "payload"            = {}
                  "parallelInvocation" = true
                  "strategy"           = "balanced"
                }
              }
              Next = "UpdateConfiguration"
            }
            UpdateConfiguration = {
              Type     = "Task"
              Resource = "arn:aws:states:::lambda:updateFunctionConfiguration"
              Parameters = {
                "FunctionName.$" = "$.functionArn"
                "MemorySize.$"   = "$.optimalMemory"
              }
              End = true
            }
          }
        }
        End = true
      }
    }
  })

  tags = var.tags
}

# Step Functions IAM Role
resource "aws_iam_role" "step_functions" {
  name = "lambda-memory-tuning-sfn-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "step_functions" {
  name = "lambda-memory-tuning-sfn-policy"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction",
          "lambda:UpdateFunctionConfiguration",
          "lambda:GetFunction",
          "lambda:ListFunctions"
        ]
        Resource = "*"
      }
    ]
  })
}

# 输出优化建议
output "memory_optimization_recommendations" {
  value = {
    for fn, config in local.memory_recommendations : fn => {
      current_memory     = config.base_memory
      recommended_memory = config.recommended_memory
      potential_savings  = config.base_memory > config.cost_optimized_memory ? "${format("%.0f", ((config.base_memory - config.cost_optimized_memory) / config.base_memory) * 100)}%" : "0%"
      performance_gain   = config.performance_optimized_memory > config.base_memory ? "${format("%.0f", ((config.performance_optimized_memory - config.base_memory) / config.base_memory) * 100)}%" : "0%"
    }
  }
  description = "Memory optimization recommendations for Lambda functions"
}

# 变量定义
variable "lambda_functions" {
  description = "Map of Lambda function names to monitor"
  type        = map(any)
  default     = {}
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}

variable "alarm_actions" {
  description = "List of ARNs to notify when alarms trigger"
  type        = list(string)
  default     = []
}