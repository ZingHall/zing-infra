output "vpc_id" {
  description = "VPC 的 ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "VPC 的 CIDR"
  value       = aws_vpc.main.cidr_block
}

output "private_nat_ips" {
  description = "所有 NAT Gateway 的 private IP"
  value       = aws_eip.nat.*.public_ip
}

output "private_subnet_ids" {
  description = "所有 private subnet 的 ID"
  value       = aws_subnet.private.*.id
}

output "public_subnet_ids" {
  description = "所有 public subnet 的 ID"
  value       = aws_subnet.public.*.id
}

output "availability_zones" {
  description = "所有 public subnet 的可用區域 (AZ)"
  value       = aws_subnet.public.*.availability_zone
}

output "private_route_table_ids" {
  description = "所有 private 路由表的 ID"
  value       = aws_route_table.private.*.id
}

output "public_route_table_ids" {
  description = "所有 public 路由表的 ID"
  value       = aws_route_table.public.*.id
}

output "internet_gateway_id" {
  description = "Internet Gateway 的 ID"
  value       = aws_internet_gateway.igw.id
}

output "private_subnet_cidrs" {
  description = "所有 private subnet 的 CIDR"
  value       = aws_subnet.private.*.cidr_block
}

output "public_subnet_cidrs" {
  description = "所有 public subnet 的 CIDR"
  value       = aws_subnet.public.*.cidr_block
}



