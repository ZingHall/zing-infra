resource "aws_iam_role" "waf_logging_role" {
  name = "${var.name}-waf-logging-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "wafv2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.name}-waf-logging-role"
  }
}

resource "aws_iam_role_policy" "waf_logging_policy" {
  name = "${var.name}-waf-logging-policy"
  role = aws_iam_role.waf_logging_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.waf_logs.arn}:*"
      }
    ]
  })
}
