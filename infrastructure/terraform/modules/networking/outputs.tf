# 网络模块输出

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR块"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "公有子网ID列表"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "私有子网ID列表"
  value       = aws_subnet.private[*].id
}

output "nat_gateway_ids" {
  description = "NAT网关ID列表"
  value       = aws_nat_gateway.main[*].id
}

output "lambda_security_group_id" {
  description = "Lambda安全组ID"
  value       = aws_security_group.lambda.id
}

output "vpc_endpoints_security_group_id" {
  description = "VPC端点安全组ID"
  value       = aws_security_group.vpc_endpoints.id
}

output "s3_vpc_endpoint_id" {
  description = "S3 VPC端点ID"
  value       = aws_vpc_endpoint.s3.id
}

output "bedrock_vpc_endpoint_id" {
  description = "Bedrock VPC端点ID"
  value       = try(aws_vpc_endpoint.bedrock[0].id, null)
}

output "bedrock_runtime_vpc_endpoint_id" {
  description = "Bedrock Runtime VPC端点ID"
  value       = try(aws_vpc_endpoint.bedrock_runtime[0].id, null)
}