# VPC Endpoints for us-east-2 VPC
# These allow ECS instances to access AWS services without Internet Gateway or NAT
# All traffic stays within AWS network
# Note: us_east_2_vpc_cidr is defined in vpc-us-east-2.tf locals

# S3 Gateway Endpoint (free, no ENI needed)
resource "aws_vpc_endpoint" "s3" {
  provider = aws.us_east_2

  vpc_id            = aws_vpc.us_east_2.id
  service_name      = "com.amazonaws.us-east-2.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.us_east_2_private[*].id

  tags = {
    Name = "zing-staging-us-east-2-s3-endpoint"
  }
}

# ECR API Endpoint (for pulling Docker images)
resource "aws_vpc_endpoint" "ecr_api" {
  provider = aws.us_east_2

  vpc_id              = aws_vpc.us_east_2.id
  service_name        = "com.amazonaws.us-east-2.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.us_east_2_private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "zing-staging-us-east-2-ecr-api-endpoint"
  }
}

# ECR DKR Endpoint (for Docker registry)
resource "aws_vpc_endpoint" "ecr_dkr" {
  provider = aws.us_east_2

  vpc_id              = aws_vpc.us_east_2.id
  service_name        = "com.amazonaws.us-east-2.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.us_east_2_private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "zing-staging-us-east-2-ecr-dkr-endpoint"
  }
}

# CloudWatch Logs Endpoint
resource "aws_vpc_endpoint" "cloudwatch_logs" {
  provider = aws.us_east_2

  vpc_id              = aws_vpc.us_east_2.id
  service_name        = "com.amazonaws.us-east-2.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.us_east_2_private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "zing-staging-us-east-2-cloudwatch-logs-endpoint"
  }
}

# Secrets Manager Endpoint
resource "aws_vpc_endpoint" "secrets_manager" {
  provider = aws.us_east_2

  vpc_id              = aws_vpc.us_east_2.id
  service_name        = "com.amazonaws.us-east-2.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.us_east_2_private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "zing-staging-us-east-2-secrets-manager-endpoint"
  }
}

# SSM Endpoint (for Systems Manager access)
resource "aws_vpc_endpoint" "ssm" {
  provider = aws.us_east_2

  vpc_id              = aws_vpc.us_east_2.id
  service_name        = "com.amazonaws.us-east-2.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.us_east_2_private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "zing-staging-us-east-2-ssm-endpoint"
  }
}

# SSM Messages Endpoint
resource "aws_vpc_endpoint" "ssm_messages" {
  provider = aws.us_east_2

  vpc_id              = aws_vpc.us_east_2.id
  service_name        = "com.amazonaws.us-east-2.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.us_east_2_private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "zing-staging-us-east-2-ssm-messages-endpoint"
  }
}

# EC2 Messages Endpoint (for ECS agent)
resource "aws_vpc_endpoint" "ec2_messages" {
  provider = aws.us_east_2

  vpc_id              = aws_vpc.us_east_2.id
  service_name        = "com.amazonaws.us-east-2.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.us_east_2_private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "zing-staging-us-east-2-ec2-messages-endpoint"
  }
}

# Security Group for VPC Endpoints
resource "aws_security_group" "vpc_endpoints" {
  provider = aws.us_east_2

  name        = "zing-staging-us-east-2-vpc-endpoints-sg"
  description = "Security group for VPC endpoints in us-east-2"
  vpc_id      = aws_vpc.us_east_2.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.1.0.0/16"] # us-east-2 VPC CIDR
    description = "Allow HTTPS from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name = "zing-staging-us-east-2-vpc-endpoints-sg"
  }
}

