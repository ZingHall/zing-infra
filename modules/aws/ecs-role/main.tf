# ECS Task Execution Role
resource "aws_iam_role" "execution" {
  name = "${var.name}-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# Attach AWS managed policy for ECS task execution
resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Additional policy for secrets and SSM access
resource "aws_iam_role_policy" "execution_secrets" {
  count = var.enable_secrets_access ? 1 : 0

  name = "${var.name}-secrets-access"
  role = aws_iam_role.execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "kms:Decrypt"
        ]
        Resource = var.secrets_arns
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameters",
          "ssm:GetParameter"
        ]
        Resource = var.ssm_parameter_arns
      }
    ]
  })
}

# Custom execution role policies
resource "aws_iam_role_policy" "execution_custom" {
  for_each = var.execution_role_policies

  name   = each.key
  role   = aws_iam_role.execution.id
  policy = each.value
}

# ECS Task Role (for application permissions)
resource "aws_iam_role" "task" {
  name = "${var.name}-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# Basic task role policy (CloudWatch Logs)
resource "aws_iam_role_policy" "task_logs" {
  name = "${var.name}-logs-policy"
  role = aws_iam_role.task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = var.log_group_arn != "" ? "${var.log_group_arn}:*" : "*"
      }
    ]
  })
}

# Custom task role policies
resource "aws_iam_role_policy" "task_custom" {
  for_each = var.task_role_policies

  name   = each.key
  role   = aws_iam_role.task.id
  policy = each.value
}

# Data sources
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

