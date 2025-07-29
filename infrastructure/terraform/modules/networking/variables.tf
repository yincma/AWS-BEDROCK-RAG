# 网络模块变量定义

variable "project_name" {
  description = "项目名称"
  type        = string
}

variable "environment" {
  description = "环境名称 (dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS区域"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "VPC CIDR块"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "公有子网CIDR块列表"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "私有子网CIDR块列表"
  type        = list(string)
}

variable "availability_zones" {
  description = "可用区列表"
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "是否启用NAT网关"
  type        = bool
  default     = true
}

variable "enable_vpc_endpoints" {
  description = "是否启用VPC端点"
  type        = bool
  default     = true
}

variable "common_tags" {
  description = "通用标签"
  type        = map(string)
  default     = {}
}