data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

# Get latest Amazon Linux 2 AMI if not provided
data "aws_ami" "amazon_linux" {
  count       = var.ami_id == null ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security Group for Enclave instances
resource "aws_security_group" "enclave" {
  name        = "${var.name}-enclave-sg"
  description = "Security group for Nitro Enclave EC2 instances"
  vpc_id      = var.vpc_id

  # Note: Ingress rules are managed separately using aws_security_group_rule resources
  # in the environment configuration for better flexibility (e.g., ALB integration)

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  # Tags: Name tag only (provider default_tags will be automatically applied)
  tags = {
    Name = "${var.name}-enclave-sg"
  }
}

# IAM Role for EC2 instances
resource "aws_iam_role" "enclave" {
  name = "${var.name}-enclave-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  # Note: Tags are merged with provider default_tags
  # Ensure no duplicate keys (AWS tag keys are case-insensitive)
  tags = {
    Name = "${var.name}-enclave-role"
  }
}

# IAM Policy for S3 access
resource "aws_iam_role_policy" "s3_access" {
  name = "${var.name}-s3-access"
  role = aws_iam_role.enclave.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "${var.s3_bucket_arn}/*",
          var.s3_bucket_arn
        ]
      }
    ]
  })
}

# IAM Policy for Secrets Manager access
resource "aws_iam_role_policy" "secrets_access" {
  count = length(var.secrets_arns) > 0 ? 1 : 0
  name  = "${var.name}-secrets-access"
  role  = aws_iam_role.enclave.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = var.secrets_arns
      }
    ]
  })
}

# IAM Policy for CloudWatch Logs
resource "aws_iam_role_policy" "cloudwatch_logs" {
  name = "${var.name}-cloudwatch-logs"
  role = aws_iam_role.enclave.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DescribeLogGroups"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/ec2/${var.name}"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/ec2/${var.name}:*"
      }
    ]
  })
}

# Attach AWS managed policy for SSM (required for SSM Session Manager)
resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.enclave.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "enclave" {
  name = "${var.name}-enclave-profile"
  role = aws_iam_role.enclave.name

  # Tags: Name tag only (provider default_tags will be automatically applied)
  tags = {
    Name = "${var.name}-enclave-profile"
  }
}

# Launch Template
resource "aws_launch_template" "enclave" {
  name_prefix   = "${var.name}-"
  image_id      = var.ami_id != null ? var.ami_id : data.aws_ami.amazon_linux[0].id
  instance_type = var.instance_type

  # Use network_interfaces when public IP is enabled, otherwise use vpc_security_group_ids
  # Note: When using network_interfaces, we must specify device_index = 0 for the primary interface
  dynamic "network_interfaces" {
    for_each = var.enable_public_ip ? [1] : []
    content {
      device_index                = 0
      associate_public_ip_address = true
      security_groups             = [aws_security_group.enclave.id]
      delete_on_termination       = true
    }
  }

  # Only use vpc_security_group_ids when public IP is disabled
  # When using network_interfaces, vpc_security_group_ids must be empty
  vpc_security_group_ids = var.enable_public_ip ? [] : [aws_security_group.enclave.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.enclave.name
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.root_volume_size
      volume_type           = var.root_volume_type
      delete_on_termination = true
      encrypted             = true
    }
  }

  # Enable Nitro Enclaves
  enclave_options {
    enabled = true
  }

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    s3_bucket         = var.s3_bucket_name
    eif_version       = var.eif_version
    eif_path          = var.eif_path
    enclave_cpu       = var.enclave_cpu_count
    enclave_memory    = var.enclave_memory_mb
    enclave_port      = var.enclave_port
    enclave_init_port = var.enclave_init_port
    name              = var.name
    region            = data.aws_region.current.name
    log_group_name    = aws_cloudwatch_log_group.enclave.name
    extra_user_data   = var.user_data_extra
  }))

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  tag_specifications {
    resource_type = "instance"
    # Tags: Name tag only (provider default_tags will be automatically applied)
    tags = {
      Name = var.name
    }
  }

  tag_specifications {
    resource_type = "volume"
    # Tags: Name tag only (provider default_tags will be automatically applied)
    tags = {
      Name = "${var.name}-volume"
    }
  }

  # Tags: Name tag only (provider default_tags will be automatically applied)
  tags = {
    Name = "${var.name}-launch-template"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "enclave" {
  name                      = "${var.name}-asg"
  vpc_zone_identifier       = var.subnet_ids
  min_size                  = var.min_size
  max_size                  = var.max_size
  desired_capacity          = var.desired_capacity
  health_check_type         = "ELB"
  health_check_grace_period = var.health_check_grace_period

  launch_template {
    id      = aws_launch_template.enclave.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = var.name
    propagate_at_launch = true
  }

  # Note: Provider default_tags will be automatically applied
  # No need to add var.tags here to avoid duplicate tag keys

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Policies (optional)
resource "aws_autoscaling_policy" "cpu_scaling" {
  count                  = var.enable_auto_scaling ? 1 : 0
  name                   = "${var.name}-cpu-scaling"
  autoscaling_group_name = aws_autoscaling_group.enclave.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.target_cpu_utilization
  }
}

# Note: AWS Auto Scaling does not support memory-based scaling
# Only CPU, Network, and ALB request count metrics are supported
# Memory scaling would require custom CloudWatch metrics and alarms

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "enclave" {
  name              = "/aws/ec2/${var.name}"
  retention_in_days = 7

  # Tags: Name tag only (provider default_tags will be automatically applied)
  tags = {
    Name = "${var.name}-logs"
  }
}


