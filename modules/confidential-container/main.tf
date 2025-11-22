data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

# Get latest Amazon Linux 2023 AMI with UEFI boot support
data "aws_ami" "amazon_linux_2023" {
  count       = var.ami_id == null && var.ami_os == "amazon-linux-2023" ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "boot-mode"
    values = ["uefi-preferred", "uefi"]
  }
}

# Get latest Ubuntu 22.04+ AMI with UEFI boot support
data "aws_ami" "ubuntu" {
  count       = var.ami_id == null && var.ami_os == "ubuntu" ? 1 : 0
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "boot-mode"
    values = ["uefi-preferred", "uefi"]
  }
}

# Determine AMI ID
locals {
  ami_id = var.ami_id != null ? var.ami_id : (
    var.ami_os == "amazon-linux-2023" ? data.aws_ami.amazon_linux_2023[0].id : (
      var.ami_os == "ubuntu" ? data.aws_ami.ubuntu[0].id : null
    )
  )
}

# Security Group for ECS instances
resource "aws_security_group" "ecs" {
  name        = "${var.name}-ecs-sg"
  description = "Security group for ECS confidential container instances"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(var.tags, {
    Name = "${var.name}-ecs-sg"
  })
}

# Security group rules for Enclave mTLS connectivity
# Note: If enclave_security_group_ids is empty, we assume cross-region and use CIDR blocks
# This is handled by the calling module via separate security group rules
resource "aws_security_group_rule" "enclave_ingress" {
  count = var.enable_enclave_mtls && length(var.enclave_security_group_ids) > 0 ? 1 : 0

  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = var.enclave_security_group_ids[0]
  security_group_id        = aws_security_group.ecs.id
  description              = "Allow inbound from Nitro Enclave security group for mTLS"
}

# Allow ECS instances to connect to Enclave security groups
resource "aws_security_group_rule" "enclave_egress" {
  count = var.enable_enclave_mtls && length(var.enclave_security_group_ids) > 0 ? length(var.enclave_security_group_ids) : 0

  type                     = "egress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = var.enclave_security_group_ids[count.index]
  security_group_id        = aws_security_group.ecs.id
  description              = "Allow outbound to Nitro Enclave for mTLS connections"
}

# IAM Role for ECS EC2 instances
resource "aws_iam_role" "ecs_instance" {
  name = "${var.name}-ecs-instance-role"

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

  tags = merge(var.tags, {
    Name = "${var.name}-ecs-instance-role"
  })
}

# Attach AWS managed policy for ECS instances
resource "aws_iam_role_policy_attachment" "ecs_instance" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# Attach AWS managed policy for SSM (enables SSM Agent to connect)
resource "aws_iam_role_policy_attachment" "ssm_instance" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM Policy for Secrets Manager access (mTLS certificates)
resource "aws_iam_role_policy" "secrets_access" {
  count = var.enable_enclave_mtls && length(var.mtls_certificate_secrets_arns) > 0 ? 1 : 0
  name  = "${var.name}-secrets-access"
  role  = aws_iam_role.ecs_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = var.mtls_certificate_secrets_arns
      }
    ]
  })
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "ecs_instance" {
  name = "${var.name}-ecs-instance-profile"
  role = aws_iam_role.ecs_instance.name

  tags = merge(var.tags, {
    Name = "${var.name}-ecs-instance-profile"
  })
}

# Launch Template for ECS instances with AMD SEV-SNP
resource "aws_launch_template" "ecs" {
  name_prefix   = "${var.name}-"
  image_id      = local.ami_id
  instance_type = var.instance_type

  # Enable AMD SEV-SNP via CPU options
  # Note: UEFI boot mode is ensured by selecting UEFI-compatible AMIs
  cpu_options {
    amd_sev_snp = "enabled"
  }

  # Network configuration
  vpc_security_group_ids = [aws_security_group.ecs.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance.name
  }

  # Block device mappings
  block_device_mappings {
    device_name = var.root_device_name
    ebs {
      volume_size           = var.root_volume_size
      volume_type           = var.root_volume_type
      delete_on_termination = true
      encrypted             = true
    }
  }

  # User data for ECS agent installation
  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    cluster_name             = aws_ecs_cluster.this.name
    region                   = data.aws_region.current.name
    extra_user_data          = var.user_data_extra
    ami_os                   = var.ami_os
    enable_enclave_mtls      = var.enable_enclave_mtls
    mtls_certificate_secrets = join(",", var.mtls_certificate_secrets_arns)
    mtls_certificate_path    = var.mtls_certificate_path
    enclave_endpoints        = join(",", var.enclave_endpoints)
    log_group_name           = var.log_group_name
  }))

  # Metadata options
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  # Tag specifications
  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${var.name}-ecs-instance"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.tags, {
      Name = "${var.name}-ecs-volume"
    })
  }

  tags = merge(var.tags, {
    Name = "${var.name}-launch-template"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group for ECS instances
resource "aws_autoscaling_group" "ecs" {
  name                = "${var.name}-asg"
  vpc_zone_identifier = var.subnet_ids
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.desired_capacity

  launch_template {
    id      = aws_launch_template.ecs.id
    version = "$Latest"
  }

  health_check_type         = "EC2"
  health_check_grace_period = var.health_check_grace_period

  # Protect from scale-in during deployments
  # If managed termination protection is enabled, we must enable scale-in protection
  protect_from_scale_in = var.managed_termination_protection ? true : var.protect_from_scale_in

  # Tag instances for ECS cluster discovery
  tag {
    key                 = "Name"
    value               = "${var.name}-ecs-instance"
    propagate_at_launch = true
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = "true"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
    # Note: desired_capacity is managed by Terraform
    # Remove ignore_changes to allow Terraform to manage desired capacity
  }
}

# CloudWatch Log Group for instance logs
resource "aws_cloudwatch_log_group" "instance_logs" {
  count             = var.log_group_name != "" ? 1 : 0
  name              = var.log_group_name
  retention_in_days = 7

  tags = merge(var.tags, {
    Name = "${var.name}-instance-logs"
  })
}

# IAM Policy for CloudWatch Logs access
resource "aws_iam_role_policy" "cloudwatch_logs" {
  count = var.log_group_name != "" ? 1 : 0
  name  = "${var.name}-cloudwatch-logs"
  role  = aws_iam_role.ecs_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.instance_logs[0].arn}:*"
        ]
      }
    ]
  })
}

# ECS Cluster
resource "aws_ecs_cluster" "this" {
  name = var.name

  setting {
    name  = "containerInsights"
    value = var.container_insights_enabled ? "enabled" : "disabled"
  }

  dynamic "service_connect_defaults" {
    for_each = var.service_connect_namespace != "" ? [1] : []

    content {
      namespace = var.service_connect_namespace
    }
  }

  tags = var.tags
}

# ECS Cluster Capacity Provider
resource "aws_ecs_capacity_provider" "this" {
  name = "${var.name}-cp"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs.arn
    managed_termination_protection = var.managed_termination_protection ? "ENABLED" : "DISABLED"

    managed_scaling {
      maximum_scaling_step_size = var.max_scaling_step_size
      minimum_scaling_step_size = var.min_scaling_step_size
      status                    = var.enable_managed_scaling ? "ENABLED" : "DISABLED"
      target_capacity           = var.target_capacity
    }
  }

  tags = var.tags
}

# Associate capacity provider with cluster
resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name = aws_ecs_cluster.this.name

  capacity_providers = [aws_ecs_capacity_provider.this.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.this.name
    weight            = 1
    base              = var.base_capacity
  }
}

# Auto Scaling policies (optional)
resource "aws_autoscaling_policy" "scale_up" {
  count                  = var.enable_auto_scaling ? 1 : 0
  name                   = "${var.name}-scale-up"
  autoscaling_group_name = aws_autoscaling_group.ecs.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 300
}

resource "aws_autoscaling_policy" "scale_down" {
  count                  = var.enable_auto_scaling ? 1 : 0
  name                   = "${var.name}-scale-down"
  autoscaling_group_name = aws_autoscaling_group.ecs.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 300
}

# CloudWatch alarms for auto scaling
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  count               = var.enable_auto_scaling ? 1 : 0
  alarm_name          = "${var.name}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = var.target_cpu_utilization
  alarm_description   = "This metric monitors ECS CPU utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_up[0].arn]

  dimensions = {
    ClusterName = aws_ecs_cluster.this.name
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  count               = var.enable_auto_scaling ? 1 : 0
  alarm_name          = "${var.name}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = var.target_cpu_utilization - 20
  alarm_description   = "This metric monitors ECS CPU utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_down[0].arn]

  dimensions = {
    ClusterName = aws_ecs_cluster.this.name
  }
}

