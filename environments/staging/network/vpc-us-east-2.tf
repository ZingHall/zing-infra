# VPC for us-east-2 (AMD SEV-SNP region)
# This VPC will be peered with the main VPC in ap-northeast-1
# No Internet Gateway or NAT Gateway - all traffic routes through VPC Peering

data "aws_availability_zones" "us_east_2" {
  provider = aws.us_east_2
}

locals {
  us_east_2_az_count = 2
  us_east_2_azs      = slice(data.aws_availability_zones.us_east_2.names, 0, local.us_east_2_az_count)
  # Use different CIDR to avoid conflicts with ap-northeast-1 VPC (10.0.0.0/16)
  # This is the single source of truth for us-east-2 VPC CIDR
  us_east_2_vpc_cidr = "10.1.0.0/16"
}

# Provider for us-east-2
provider "aws" {
  alias   = "us_east_2"
  region  = "us-east-2"
  profile = "zing-staging"

  default_tags {
    tags = {
      environment = "staging"
      module      = "network-us-east-2"
      managed_by  = "terraform"
    }
  }
}

# VPC in us-east-2
resource "aws_vpc" "us_east_2" {
  provider = aws.us_east_2

  cidr_block                       = local.us_east_2_vpc_cidr
  instance_tenancy                 = "default"
  assign_generated_ipv6_cidr_block = false
  enable_dns_support               = true
  enable_dns_hostnames             = true

  tags = {
    Name = "zing-staging-us-east-2-vpc"
  }
}

# Private Subnets in us-east-2 (only private subnets, no public subnets)
resource "aws_subnet" "us_east_2_private" {
  provider          = aws.us_east_2
  count             = local.us_east_2_az_count
  vpc_id            = aws_vpc.us_east_2.id
  cidr_block        = cidrsubnet(local.us_east_2_vpc_cidr, 8, count.index + 100)
  availability_zone = local.us_east_2_azs[count.index]

  tags = {
    Name = "zing-staging-us-east-2-private-${count.index + 1}"
    Type = "private"
  }
}

# Private Route Table for us-east-2
resource "aws_route_table" "us_east_2_private" {
  provider = aws.us_east_2
  count    = local.us_east_2_az_count
  vpc_id   = aws_vpc.us_east_2.id

  tags = {
    Name = "zing-staging-us-east-2-private-rt-${count.index + 1}"
  }
}

# Private Route Table Association
resource "aws_route_table_association" "us_east_2_private" {
  provider       = aws.us_east_2
  count          = local.us_east_2_az_count
  subnet_id      = aws_subnet.us_east_2_private[count.index].id
  route_table_id = aws_route_table.us_east_2_private[count.index].id
}

# Note: Routes to ap-northeast-1 VPC via VPC Peering are configured in vpc-peering.tf
