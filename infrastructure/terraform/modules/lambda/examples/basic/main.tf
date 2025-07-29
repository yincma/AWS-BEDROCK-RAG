# 基本 Lambda 函数示例

# 创建 IAM 角色
module "lambda_role" {
  source = "../../../iam"

  name_prefix = "example-lambda"

  lambda_policy_statements = [
    {
      actions = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      resources = ["arn:aws:logs:*:*:*"]
    }
  ]

  tags = {
    Environment = "dev"
    Example     = "basic"
  }
}

# 创建 Lambda 函数
module "lambda" {
  source = "../../"

  function_name = "example-basic-function"
  description   = "基本 Lambda 函数示例"

  # 使用本地 ZIP 文件
  deployment_package_type = "zip"
  filename                = "lambda_function.zip"
  source_code_hash        = filebase64sha256("lambda_function.zip")

  runtime = "python3.9"
  handler = "index.handler"

  role_arn    = module.lambda_role.lambda_role_arn
  timeout     = 30
  memory_size = 256

  environment_variables = {
    ENVIRONMENT = "dev"
    LOG_LEVEL   = "INFO"
  }

  tags = {
    Environment = "dev"
    Example     = "basic"
  }
}

# 输出
output "function_name" {
  value = module.lambda.function_name
}

output "function_arn" {
  value = module.lambda.function_arn
}

output "log_group_name" {
  value = module.lambda.log_group_name
}