# 完整 Lambda 函数示例（包含所有高级功能）

# VPC 配置（示例）
data "aws_vpc" "example" {
  default = true
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.example.id]
  }
}

# 创建安全组
resource "aws_security_group" "lambda" {
  name_prefix = "lambda-example-"
  vpc_id      = data.aws_vpc.example.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 创建 EFS 文件系统（示例）
resource "aws_efs_file_system" "lambda" {
  encrypted = true

  tags = {
    Name = "lambda-efs-example"
  }
}

resource "aws_efs_access_point" "lambda" {
  file_system_id = aws_efs_file_system.lambda.id

  posix_user {
    gid = 1000
    uid = 1000
  }

  root_directory {
    path = "/lambda"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }
}

# 创建 SQS 死信队列
resource "aws_sqs_queue" "dlq" {
  name = "lambda-example-dlq"

  tags = {
    Purpose = "Lambda DLQ"
  }
}

# 创建 SNS 主题（用于异步调用目标）
resource "aws_sns_topic" "success" {
  name = "lambda-example-success"
}

resource "aws_sns_topic" "failure" {
  name = "lambda-example-failure"
}

# 创建 IAM 角色
module "lambda_role" {
  source = "../../../iam"

  name_prefix = "example-lambda-complete"

  enable_vpc_config   = true
  enable_xray_tracing = true

  lambda_policy_statements = [
    {
      actions = [
        "s3:GetObject",
        "s3:PutObject"
      ]
      resources = ["arn:aws:s3:::my-bucket/*"]
    },
    {
      actions = [
        "sqs:SendMessage"
      ]
      resources = [aws_sqs_queue.dlq.arn]
    },
    {
      actions = [
        "sns:Publish"
      ]
      resources = [
        aws_sns_topic.success.arn,
        aws_sns_topic.failure.arn
      ]
    },
    {
      actions = [
        "elasticfilesystem:ClientMount",
        "elasticfilesystem:ClientWrite"
      ]
      resources = ["*"]
    }
  ]

  tags = {
    Environment = "prod"
    Example     = "complete"
  }
}

# 创建 Lambda 层
module "lambda" {
  source = "../../"

  function_name = "example-complete-function"
  description   = "完整功能的 Lambda 函数示例"

  # 使用容器镜像部署
  deployment_package_type = "container"
  container_image_uri     = "123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app:latest"

  # 容器配置
  image_config = {
    command           = ["app.handler"]
    working_directory = "/var/task"
  }

  # 高级配置
  architecture                      = "arm64" # 使用 Graviton2
  timeout                           = 900     # 15 分钟
  memory_size                       = 3008    # 3GB
  reserved_concurrent_executions    = 100     # 预留并发
  provisioned_concurrent_executions = 10      # 预配置并发

  # VPC 配置
  vpc_config = {
    subnet_ids         = data.aws_subnets.private.ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  # EFS 挂载
  efs_mount_configs = [
    {
      efs_access_point_arn = aws_efs_access_point.lambda.arn
      local_mount_path     = "/mnt/efs"
    }
  ]

  # 死信队列
  dead_letter_config = {
    target_arn = aws_sqs_queue.dlq.arn
  }

  # X-Ray 追踪
  tracing_mode = "Active"

  # 临时存储
  ephemeral_storage_size = 2048 # 2GB

  # SnapStart
  enable_snap_start = true

  # 日志配置
  logging_config = {
    log_format            = "JSON"
    system_log_level      = "WARN"
    application_log_level = "INFO"
  }

  log_retention_days = 30
  logs_kms_key_id    = aws_kms_key.logs.arn

  # 环境变量
  environment_variables = {
    ENVIRONMENT = "production"
    LOG_LEVEL   = "INFO"
    S3_BUCKET   = "my-bucket"
    EFS_MOUNT   = "/mnt/efs"
    FEATURE_FLAGS = jsonencode({
      new_algorithm = true
      debug_mode    = false
    })
  }

  # Lambda 层
  layers = {
    "common-utils" = {
      description              = "通用工具层"
      filename                 = "layers/common-utils.zip"
      compatible_runtimes      = ["python3.9", "python3.10"]
      compatible_architectures = ["arm64"]
    }
    "ml-dependencies" = {
      description         = "机器学习依赖"
      s3_bucket           = "my-layers-bucket"
      s3_key              = "ml-deps-v2.1.0.zip"
      compatible_runtimes = ["python3.9"]
    }
  }

  # 创建函数 URL
  create_function_url = true
  function_url_config = {
    authorization_type = "AWS_IAM"
    cors = {
      allow_origins = ["https://example.com"]
      allow_methods = ["GET", "POST"]
      allow_headers = ["Content-Type", "Authorization"]
      max_age       = 86400
    }
  }

  # 创建别名
  create_alias      = true
  publish           = true
  alias_name        = "production"
  alias_description = "生产环境别名"

  # 权限配置
  lambda_permissions = {
    "api-gateway" = {
      principal  = "apigateway.amazonaws.com"
      source_arn = "arn:aws:execute-api:us-east-1:123456789012:abcdef123/*/*/*"
    }
    "s3-bucket" = {
      principal      = "s3.amazonaws.com"
      source_account = "123456789012"
      source_arn     = "arn:aws:s3:::my-bucket"
    }
  }

  # 事件源映射（SQS）
  event_source_mappings = {
    "sqs-queue" = {
      event_source_arn                   = aws_sqs_queue.events.arn
      batch_size                         = 10
      maximum_batching_window_in_seconds = 5

      filter_criteria = {
        filters = [
          {
            pattern = jsonencode({
              body = {
                type = ["order", "payment"]
              }
            })
          }
        ]
      }
    }
  }

  # 异步调用配置
  async_invoke_config = {
    maximum_event_age_in_seconds = 21600 # 6 小时
    maximum_retry_attempts       = 2

    destination_config = {
      on_success = {
        destination = aws_sns_topic.success.arn
      }
      on_failure = {
        destination = aws_sns_topic.failure.arn
      }
    }
  }

  role_arn = module.lambda_role.lambda_role_arn

  tags = {
    Environment = "prod"
    Example     = "complete"
    Team        = "platform"
  }
}

# KMS 密钥（用于日志加密）
resource "aws_kms_key" "logs" {
  description = "Lambda 日志加密密钥"
}

# SQS 队列（事件源）
resource "aws_sqs_queue" "events" {
  name = "lambda-example-events"
}

# 输出
output "function_details" {
  value = {
    name         = module.lambda.function_name
    arn          = module.lambda.function_arn
    version      = module.lambda.function_version
    alias_arn    = module.lambda.alias_arn
    function_url = module.lambda.function_url
  }
}

output "layer_arns" {
  value = module.lambda.layer_arns
}

output "monitoring" {
  value = {
    log_group = module.lambda.log_group_name
    dlq_arn   = aws_sqs_queue.dlq.arn
  }
}