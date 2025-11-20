# 使用官方的 fck-nat Terraform 模組
module "fck_nat" {
  source = "git::https://github.com/RaJiska/terraform-aws-fck-nat.git"

  # 基本配置
  name      = var.name
  vpc_id    = var.vpc_id
  subnet_id = var.subnet_id

  # 安全群組配置
  additional_security_group_ids = var.additional_security_group_ids

  # 路由表配置
  update_route_tables = true
  route_tables_ids    = var.private_subnet_route_table_map

  # SSH 配置
  use_ssh      = true
  ssh_key_name = aws_key_pair.bastion.key_name
  ssh_cidr_blocks = {
    ipv4 = var.allowed_cidr_blocks
    ipv6 = []
  }

  # 實例配置
  instance_type = var.instance_type

  # 彈性IP配置
  eip_allocation_ids = var.allocate_eip ? [aws_eip.nat[0].id] : []

  # 標籤
  tags = merge(var.tags, {
    purpose = "nat-gateway"
  })
}

# 金鑰對
resource "aws_key_pair" "bastion" {
  key_name   = "${var.name}-key"
  public_key = var.ssh_public_key

  tags = merge(var.tags, {
    name = "${var.name}-key"
  })
}

# 彈性IP（可選）
resource "aws_eip" "nat" {
  count = var.allocate_eip ? 1 : 0

  domain = "vpc"

  tags = merge(var.tags, {
    name                = "${var.name}-eip"
    used_by_nat_gateway = "${var.name}-nat"
  })
}

# DNS記錄（可選）
resource "aws_route53_record" "nat" {
  count = var.create_dns_record ? 1 : 0

  zone_id = var.route53_zone_id
  name    = var.dns_name
  type    = "A"

  ttl     = var.dns_ttl
  records = [aws_eip.nat[0].public_ip]
}

# Get data sources for IAM role
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Add SSM Session Manager permissions to bastion host IAM role
# Use the IAM role name output from fck-nat module
# This allows connecting from bastion to other instances via SSM
resource "aws_iam_role_policy" "bastion_ssm_session" {
  name = "${var.name}-ssm-session"
  role = module.fck_nat.role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:StartSession"
        ]
        Resource = [
          "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*",
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:document/SSM-SessionManagerRunShell"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:DescribeInstanceInformation",
          "ssm:DescribeInstanceProperties",
          "ssm:DescribeSessions",
          "ssm:GetConnectionStatus",
          "ssm:TerminateSession"
        ]
        Resource = "*"
      }
    ]
  })
}
