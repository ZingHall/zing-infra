# VPC Peering Connection between ap-northeast-1 and us-east-2

# Get the main VPC ID from the vpc-subnets module
locals {
  ap_northeast_1_vpc_id   = module.vpc_subnets.vpc_id
  ap_northeast_1_vpc_cidr = module.vpc_subnets.vpc_cidr_block
  us_east_2_vpc_id        = aws_vpc.us_east_2.id
  # us_east_2_vpc_cidr is defined in vpc-us-east-2.tf locals
}

# VPC Peering Connection (created in ap-northeast-1, requires acceptance in us-east-2)
resource "aws_vpc_peering_connection" "ap_ne_1_to_us_east_2" {
  vpc_id      = local.ap_northeast_1_vpc_id
  peer_vpc_id = local.us_east_2_vpc_id
  peer_region = "us-east-2"
  auto_accept = false # Must accept manually or via us-east-2 provider

  tags = {
    Name = "zing-staging-peering-ap-ne-1-to-us-east-2"
  }
}

# Accept the peering connection in us-east-2
resource "aws_vpc_peering_connection_accepter" "us_east_2_accepter" {
  provider                  = aws.us_east_2
  vpc_peering_connection_id = aws_vpc_peering_connection.ap_ne_1_to_us_east_2.id
  auto_accept               = true

  tags = {
    Name = "zing-staging-peering-us-east-2-accepter"
  }
}

# Route in ap-northeast-1 VPC to us-east-2 VPC
# Add route to all private route tables in ap-northeast-1
resource "aws_route" "ap_ne_1_to_us_east_2" {
  count                     = length(module.vpc_subnets.private_route_table_ids)
  route_table_id            = module.vpc_subnets.private_route_table_ids[count.index]
  destination_cidr_block    = "10.1.0.0/16" # us-east-2 VPC CIDR (defined in vpc-us-east-2.tf)
  vpc_peering_connection_id = aws_vpc_peering_connection.ap_ne_1_to_us_east_2.id
}

# Route in ap-northeast-1 VPC public route tables (if needed)
resource "aws_route" "ap_ne_1_public_to_us_east_2" {
  count                     = length(module.vpc_subnets.public_route_table_ids)
  route_table_id            = module.vpc_subnets.public_route_table_ids[count.index]
  destination_cidr_block    = "10.1.0.0/16" # us-east-2 VPC CIDR (defined in vpc-us-east-2.tf)
  vpc_peering_connection_id = aws_vpc_peering_connection.ap_ne_1_to_us_east_2.id
}

# Route in us-east-2 VPC to ap-northeast-1 VPC
# Add route to all private route tables in us-east-2
resource "aws_route" "us_east_2_to_ap_ne_1" {
  provider                  = aws.us_east_2
  count                     = 2 # Number of AZs in us-east-2 (defined in vpc-us-east-2.tf)
  route_table_id            = aws_route_table.us_east_2_private[count.index].id
  destination_cidr_block    = local.ap_northeast_1_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.ap_ne_1_to_us_east_2.id
}

# Note: No public subnets in us-east-2, only private subnets
# All traffic routes through VPC peering to ap-northeast-1

# Security Group Rules for cross-VPC communication
# Allow traffic from ap-northeast-1 VPC to us-east-2 resources
resource "aws_security_group_rule" "us_east_2_from_ap_ne_1" {
  provider          = aws.us_east_2
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = ["10.0.0.0/16"] # ap-northeast-1 VPC CIDR
  security_group_id = aws_security_group.us_east_2_default.id
  description       = "Allow traffic from ap-northeast-1 VPC via peering"
}

# Default security group for us-east-2 VPC (for resources that need cross-VPC access)
resource "aws_security_group" "us_east_2_default" {
  provider    = aws.us_east_2
  name        = "zing-staging-us-east-2-default-sg"
  description = "Default security group for us-east-2 VPC with peering access"
  vpc_id      = aws_vpc.us_east_2.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "zing-staging-us-east-2-default-sg"
  }
}

