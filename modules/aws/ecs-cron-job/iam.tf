# IAM Role for EventBridge to run ECS tasks
resource "aws_iam_role" "eventbridge" {
  name = "${var.name}-eventbridge-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# IAM Policy for EventBridge to run ECS tasks
resource "aws_iam_role_policy" "eventbridge_ecs" {
  name = "${var.name}-eventbridge-ecs"
  role = aws_iam_role.eventbridge.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ecs:RunTask"
        Resource = "${replace(data.aws_ecs_task_definition.this.arn, "/:\\d+$/", "")}:*"
      },
      {
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = [
          data.aws_ecs_task_definition.this.execution_role_arn,
          data.aws_ecs_task_definition.this.task_role_arn
        ]
      }
    ]
  })
}
