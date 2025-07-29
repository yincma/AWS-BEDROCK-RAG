# AWS Bedrock RAG 项目代码架构图

## 项目概述
这是一个基于AWS Bedrock的RAG（Retrieval-Augmented Generation）系统，包含前端、后端Lambda函数、基础设施代码和相关工具脚本。

## 目录结构

### 📁 根目录配置文件
- **CLAUDE.md**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/CLAUDE.md
- **README.md**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/README.md
- **requirements.txt**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/requirements.txt
- **requirements-compatible.txt**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/requirements-compatible.txt
- **project.yaml**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/project.yaml

### 🚀 部署脚本
- **deploy.sh**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/deploy.sh
- **deploy-complete.sh**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/deploy-complete.sh
- **aws-cleanup.sh**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/aws-cleanup.sh
- **（old）aws-cleanup copy.sh**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/（old）aws-cleanup copy.sh
- **build-lambda-packages.sh**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/build-lambda-packages.sh

### 📋 文档
- **DEPLOYMENT_INSTRUCTIONS.md**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/DEPLOYMENT_INSTRUCTIONS.md
- **CLEANUP_GUIDE.md**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/CLEANUP_GUIDE.md
- **TERRAFORM_MIGRATION_GUIDE.md**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/TERRAFORM_MIGRATION_GUIDE.md
- **TROUBLESHOOTING.md**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/TROUBLESHOOTING.md

### 📚 docs/ 目录
- **COGNITO_SETUP.md**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/docs/COGNITO_SETUP.md
- **deployment-guide.md**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/docs/deployment-guide.md
- **troubleshooting-guide.md**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/docs/troubleshooting-guide.md

### ⚙️ 配置文件
#### .ai-rules/ 目录
- **product.md**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/.ai-rules/product.md
- **structure.md**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/.ai-rules/structure.md
- **tech.md**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/.ai-rules/tech.md

#### .claude/ 目录
- **settings.local.json**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/.claude/settings.local.json

#### config/ 目录
- **dev.yaml**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/config/environments/dev.yaml
- **prod.yaml**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/config/environments/prod.yaml

### 🌐 前端应用 (applications/frontend/)

#### 核心源码
- **package.json**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/frontend/package.json
- **package-lock.json**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/frontend/package-lock.json
- **tsconfig.json**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/frontend/tsconfig.json
- **deploy.sh**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/frontend/deploy.sh
- **CONFIG_MANAGEMENT.md**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/frontend/CONFIG_MANAGEMENT.md

#### src/ 源码目录
- **App.css**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/frontend/src/App.css
- **index.css**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/frontend/src/index.css

##### config/ 配置
- **aws.ts**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/frontend/src/config/aws.ts
- **index.ts**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/frontend/src/config/index.ts

##### services/ 服务层
- **api.ts**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/frontend/src/services/api.ts
- **auth.ts**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/frontend/src/services/auth.ts
- **error.ts**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/frontend/src/services/error.ts
- **index.ts**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/frontend/src/services/index.ts

##### types/ 类型定义
- **index.ts**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/frontend/src/types/index.ts

#### public/ 静态资源
- **index.html**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/frontend/public/index.html
- **test.html**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/frontend/public/test.html
- **manifest.json**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/frontend/public/manifest.json
- **config.json**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/frontend/public/config.json

#### scripts/ 构建脚本
- **generate-config.js**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/frontend/scripts/generate-config.js

#### build/ 构建产物
- **index.html**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/frontend/build/index.html
- **test.html**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/frontend/build/test.html
- **asset-manifest.json**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/frontend/build/asset-manifest.json
- **manifest.json**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/frontend/build/manifest.json
- **config.json**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/frontend/build/config.json
- **main.1421f4ae.css**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/frontend/build/static/css/main.1421f4ae.css
- **main.329efb26.js**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/frontend/build/static/js/main.329efb26.js
- **main.329efb26.js.LICENSE.txt**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/frontend/build/static/js/main.329efb26.js.LICENSE.txt

### 🔧 后端应用 (applications/backend/)

#### Lambda 函数
##### authorizer/ - 认证授权器
- **authorizer.py**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/backend/lambda/authorizer/authorizer.py
- **requirements.txt**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/backend/lambda/authorizer/requirements.txt

##### document_processor/ - 文档处理器
- **handler.py**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/backend/lambda/document_processor/handler.py
- **requirements.txt**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/backend/lambda/document_processor/requirements.txt

##### index_creator/ - 索引创建器
- **index.py**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/backend/lambda/index_creator/index.py
- **requirements.txt**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/backend/lambda/index_creator/requirements.txt

##### query_handler/ - 查询处理器
- **handler.py**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/backend/lambda/query_handler/handler.py
- **requirements.txt**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/backend/lambda/query_handler/requirements.txt

##### 优化处理器
- **optimized_handler.py**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/backend/lambda/optimized_handler.py

#### layers/ - Lambda 层
##### opensearch/
- **build-layer.sh**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/backend/lambda/layers/opensearch/build-layer.sh
- **requirements.txt**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/backend/lambda/layers/opensearch/requirements.txt

##### 其他层
- **bedrock/requirements.txt**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/backend/layers/bedrock/requirements.txt
- **common/requirements.txt**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/backend/layers/common/requirements.txt
- **opensearch/requirements.txt**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/backend/layers/opensearch/requirements.txt
- **requirements.txt**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/backend/layers/requirements.txt

#### shared/ - 共享代码
- **config.py**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/backend/shared/config.py
- **error_handler.py**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/backend/shared/error_handler.py
- **lambda_base.py**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/backend/shared/lambda_base.py

##### utils/ 工具类
- **__init__.py**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/backend/shared/utils/__init__.py
- **cors.py**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/applications/backend/shared/utils/cors.py

### 🏗️ 基础设施 (infrastructure/terraform/)

#### 核心配置
- **main.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/main.tf
- **variables.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/variables.tf
- **outputs.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/outputs.tf
- **settings.local.json**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/.claude/settings.local.json

#### modules/ - Terraform 模块

##### bedrock/ 模块
- **main.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/bedrock/main.tf
- **variables.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/bedrock/variables.tf
- **outputs.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/bedrock/outputs.tf
- **lambda_index_creator.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/bedrock/lambda_index_creator.tf
- **index_creator.py**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/bedrock/index_creator.py
- **opensearch_index_init.py**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/bedrock/opensearch_index_init.py
- **lambda_requirements.txt**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/bedrock/lambda_requirements.txt

##### cognito/ 模块
- **main.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/cognito/main.tf
- **variables.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/cognito/variables.tf
- **outputs.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/cognito/outputs.tf

##### compute/ 模块
###### api_gateway/
- **main.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/compute/api_gateway/main.tf
- **variables.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/compute/api_gateway/variables.tf
- **outputs.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/compute/api_gateway/outputs.tf
- **performance.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/compute/api_gateway/performance.tf

###### lambda/
- **main.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/compute/lambda/main.tf
- **variables.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/compute/lambda/variables.tf
- **outputs.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/compute/lambda/outputs.tf

###### layers/
- **main.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/compute/layers/main.tf
- **variables.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/compute/layers/variables.tf
- **outputs.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/compute/layers/outputs.tf

##### frontend/ 模块
- **main.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/frontend/main.tf
- **variables.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/frontend/variables.tf
- **outputs.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/frontend/outputs.tf

##### iam/ 模块
- **main.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/iam/main.tf
- **variables.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/iam/variables.tf
- **outputs.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/iam/outputs.tf

##### lambda/ 模块
- **main.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/lambda/main.tf
- **variables.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/lambda/variables.tf
- **outputs.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/lambda/outputs.tf
- **autoscaling.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/lambda/autoscaling.tf
- **performance-config.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/lambda/performance-config.tf
- **performance-variables.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/lambda/performance-variables.tf
- **warmup.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/lambda/warmup.tf

###### examples/
- **basic/main.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/lambda/examples/basic/main.tf
- **complete/main.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/lambda/examples/complete/main.tf

##### monitoring/ 模块
- **main.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/monitoring/main.tf
- **variables.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/monitoring/variables.tf
- **outputs.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/monitoring/outputs.tf

###### templates/
- **canary.js**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/monitoring/templates/canary.js

###### dashboard-templates/
- **main-dashboard.json**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/monitoring/dashboard-templates/main-dashboard.json

##### networking/ 模块
- **main.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/networking/main.tf
- **variables.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/networking/variables.tf
- **outputs.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/networking/outputs.tf

##### optimization/ 模块
###### api-gateway/
- **performance.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/optimization/api-gateway/performance.tf

###### cloudwatch/
- **cost-optimization.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/optimization/cloudwatch/cost-optimization.tf
- **monitoring-optimization.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/optimization/cloudwatch/monitoring-optimization.tf

####### lambda/
- **processor.py**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/optimization/cloudwatch/lambda/processor.py
- **sampler.py**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/optimization/cloudwatch/lambda/sampler.py

###### data-compression/
- **compression.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/optimization/data-compression/compression.tf

####### lambda/
- **checker.py**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/optimization/data-compression/lambda/checker.py
- **compressor.py**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/optimization/data-compression/lambda/compressor.py

###### lambda/
- **memory-optimization.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/optimization/lambda/memory-optimization.tf
- **performance.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/optimization/lambda/performance.tf

###### s3/
- **lifecycle.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Bedrock/AWS-Bedrock-RAG/infrastructure/terraform/modules/optimization/s3/lifecycle.tf
- **storage-optimization.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/optimization/s3/storage-optimization.tf

####### lambda/
- **log-compressor.py**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/optimization/s3/lambda/log-compressor.py

##### s3/ 模块
- **main.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/s3/main.tf
- **variables.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/s3/variables.tf
- **outputs.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/s3/outputs.tf

###### examples/
- **basic/main.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/s3/examples/basic/main.tf

##### security/ 模块
- **main.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/security/main.tf
- **variables.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/security/variables.tf
- **outputs.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/security/outputs.tf

##### storage/ 模块
- **main.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/storage/main.tf
- **variables.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/storage/variables.tf
- **outputs.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/storage/outputs.tf

##### storage-optimization/ 模块
- **main.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/storage-optimization/main.tf
- **variables.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/storage-optimization/variables.tf
- **README.md**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/storage-optimization/README.md

###### cost-monitoring/
- **main.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/storage-optimization/cost-monitoring/main.tf
- **variables.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/storage-optimization/cost-monitoring/variables.tf
- **cost-calculator.py**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/storage-optimization/cost-monitoring/cost-calculator.py

###### data-compression/
- **main.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/storage-optimization/data-compression/main.tf
- **variables.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/storage-optimization/data-compression/variables.tf
- **s3-archiver.py**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/storage-optimization/data-compression/s3-archiver.py
- **s3-compressor.py**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/storage-optimization/data-compression/s3-compressor.py

###### logs-optimization/
- **main.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/storage-optimization/logs-optimization/main.tf
- **variables.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/storage-optimization/logs-optimization/variables.tf
- **log-compressor.py**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/storage-optimization/logs-optimization/log-compressor.py

###### s3-lifecycle/
- **main.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/storage-optimization/s3-lifecycle/main.tf
- **variables.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/storage-optimization/s3-lifecycle/variables.tf

###### examples/
- **complete/main.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/storage-optimization/examples/complete/main.tf

##### tags/ 模块
- **main.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/tags/main.tf
- **variables.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/tags/variables.tf
- **outputs.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/tags/outputs.tf

###### examples/
- **basic/main.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/tags/examples/basic/main.tf
- **complete/main.tf**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/tags/examples/complete/main.tf

#### 模块文档
- **README.md**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/README.md
- **common/README.md**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/common/README.md
- **ARCHITECTURE_IMPROVEMENT_REPORT.md**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/ARCHITECTURE_IMPROVEMENT_REPORT.md
- **BUSINESS_MAPPING.md**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/BUSINESS_MAPPING.md
- **COGNITO_MODULE_SEPARATION_REPORT.md**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/infrastructure/terraform/modules/COGNITO_MODULE_SEPARATION_REPORT.md

### 📊 策略和治理 (policies/)
- **enforcement-config.yaml**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/policies/enforcement-config.yaml
- **cost/README.md**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/policies/cost/README.md
- **performance/README.md**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/policies/performance/README.md
- **security/README.md**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/policies/security/README.md

### 🔧 脚本工具 (scripts/)

#### 主要脚本
- **create-test-user.sh**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/scripts/create-test-user.sh
- **deploy-api-performance.sh**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/scripts/deploy-api-performance.sh
- **deploy-frontend.sh**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/scripts/deploy-frontend.sh
- **deploy-monitoring-optimization.sh**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/scripts/deploy-monitoring-optimization.sh
- **deploy-storage-optimization.sh**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/scripts/deploy-storage-optimization.sh
- **get-knowledge-base-info.sh**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/scripts/get-knowledge-base-info.sh
- **validate-deployment.sh**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/scripts/validate-deployment.sh

#### monitoring/ 监控脚本
- **requirements.txt**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/scripts/monitoring/requirements.txt

#### utils/ 工具脚本
- **check-cloudfront-s3.sh**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/scripts/utils/check-cloudfront-s3.sh
- **cleanup.sh**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/scripts/utils/cleanup.sh
- **cleanup-s3.sh**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/scripts/utils/cleanup-s3.sh
- **common.sh**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/scripts/utils/common.sh
- **config-wizard.sh**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/scripts/utils/config-wizard.sh
- **opa-check.sh**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/scripts/utils/opa-check.sh
- **pre-check.sh**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/scripts/utils/pre-check.sh
- **validate-config.sh**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/scripts/utils/validate-config.sh

### 🧪 测试 (test/)

#### 核心测试文件
- **automated_test.py**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/test/automated_test.py
- **security_validation.py**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/test/security_validation.py
- **simple_browser_test.py**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/test/simple_browser_test.py
- **README.md**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/test/README.md
- **tasks.md**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/test/tasks.md
- **result.md**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/test/result.md
- **manual_test_report.md**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/test/manual_test_report.md
- **security_report_20250728_001710.json**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/test/security_report_20250728_001710.json

#### backend/ 后端测试
- **requirements-test.txt**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/test/backend/requirements-test.txt
- **test_query_handler.py**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/test/backend/test_query_handler.py
- **.pytest_cache/README.md**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/test/backend/.pytest_cache/README.md

#### frontend/ 前端测试
- **package.json**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/test/frontend/package.json
- **package-lock.json**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/test/frontend/package-lock.json
- **jest.config.js**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/test/frontend/jest.config.js
- **jest.setup.js**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/test/frontend/jest.setup.js
- **authService.test.ts**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/test/frontend/authService.test.ts

##### __mocks__/
- **fileMock.js**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/test/frontend/__mocks__/fileMock.js

##### coverage/ 测试覆盖率报告
- **coverage-final.json**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/test/frontend/coverage/coverage-final.json

###### lcov-report/
- **index.html**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/test/frontend/coverage/lcov-report/index.html
- **base.css**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/test/frontend/coverage/lcov-report/base.css
- **prettify.css**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/test/frontend/coverage/lcov-report/prettify.css
- **block-navigation.js**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/test/frontend/coverage/lcov-report/block-navigation.js
- **prettify.js**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/test/frontend/coverage/lcov-report/prettify.js
- **sorter.js**: /Users/umatoratatsu/Documents/AWS/AWS-Handson/AWS-Bedrock-RAG/test/frontend/coverage/lcov-report/sorter.js

## 技术栈总览

### 前端技术
- **TypeScript** - 类型安全的JavaScript
- **React** - 前端框架（根据构建文件推测）
- **CSS** - 样式表

### 后端技术
- **Python** - 主要编程语言
- **AWS Lambda** - 无服务器计算
- **OpenSearch** - 搜索和分析引擎
- **AWS Bedrock** - 机器学习基础服务

### 基础设施
- **Terraform** - 基础设施即代码
- **AWS CloudFormation** - AWS原生基础设施管理
- **Shell Scripts** - 自动化部署脚本

### 测试框架
- **Jest** - JavaScript测试框架
- **pytest** - Python测试框架

### 开发工具
- **Claude Code** - AI辅助开发工具
- **Git** - 版本控制

## 项目特点

1. **模块化架构** - 清晰的前后端分离，基础设施代码模块化
2. **云原生设计** - 基于AWS服务的无服务器架构
3. **自动化部署** - 完整的CI/CD脚本和基础设施自动化
4. **测试覆盖** - 前端和后端都有完整的测试套件
5. **文档完善** - 详细的部署说明、故障排除和架构文档
6. **性能优化** - 包含多种优化策略（存储、监控、API等）
7. **安全性** - 集成Cognito认证和安全验证

## 总结

这是一个企业级的AWS Bedrock RAG系统，采用现代化的云原生架构，具有完整的前后端应用、基础设施代码、部署脚本、测试套件和文档。项目结构清晰，模块化程度高，便于维护和扩展。