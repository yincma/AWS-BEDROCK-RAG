# 使用 AWS Lambda Python 运行时镜像
FROM public.ecr.aws/lambda/python:3.11

# 设置工作目录
WORKDIR /opt

# 复制 requirements 文件
COPY requirements.txt .

# 安装依赖到 python 目录（Lambda 层的标准路径）
RUN pip install -r requirements.txt -t python/ --no-cache-dir

# 安装 zip 工具
RUN yum install -y zip

# 创建层的 ZIP 文件
RUN cd /opt && zip -r opensearch-layer.zip python/

# 设置输出目录
CMD ["cp", "/opt/opensearch-layer.zip", "/output/"]