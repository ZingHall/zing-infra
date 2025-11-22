output "hosted_zone_id" {
  value = aws_route53_zone.hosted_zone.zone_id
}

output "hosted_zone_name" {
  value = aws_route53_zone.hosted_zone.name
}

output "vpc_cidr_block" {
  description = "The CIDR block of the main VPC."
  value       = module.vpc_subnets.vpc_cidr_block
}

output "vpc_id" {
  description = "The ID of the main VPC."
  value       = module.vpc_subnets.vpc_id
}

output "private_subnet_ids" {
  description = "The IDs of the private subnets."
  value       = module.vpc_subnets.private_subnet_ids
}

output "public_subnet_ids" {
  description = "The IDs of the public subnets."
  value       = module.vpc_subnets.public_subnet_ids
}

output "private_subnet_nat_ips" {
  description = "A list of the public elastic IPs associated with the NAT gateways in this VPC."
  value       = module.vpc_subnets.private_nat_ips
}

output "availability_zones" {
  description = "A list of availability zones in the region."
  value       = module.vpc_subnets.availability_zones
}

output "private_route_table_ids" {
  description = "The IDs of the private route tables."
  value       = module.vpc_subnets.private_route_table_ids
}

output "public_route_table_ids" {
  description = "The IDs of the public route tables."
  value       = module.vpc_subnets.public_route_table_ids
}

# us-east-2 VPC Outputs
output "us_east_2_vpc_id" {
  description = "The ID of the us-east-2 VPC."
  value       = aws_vpc.us_east_2.id
}

output "us_east_2_vpc_cidr_block" {
  description = "The CIDR block of the us-east-2 VPC."
  value       = "10.1.0.0/16"
}

output "us_east_2_private_subnet_ids" {
  description = "The IDs of the private subnets in us-east-2."
  value       = aws_subnet.us_east_2_private[*].id
}

output "us_east_2_private_route_table_ids" {
  description = "The IDs of the private route tables in us-east-2."
  value       = aws_route_table.us_east_2_private[*].id
}

output "vpc_peering_connection_id" {
  description = "The ID of the VPC peering connection."
  value       = aws_vpc_peering_connection.ap_ne_1_to_us_east_2.id
}

output "us_east_2_default_security_group_id" {
  description = "The ID of the default security group in us-east-2 VPC."
  value       = aws_security_group.us_east_2_default.id
}
