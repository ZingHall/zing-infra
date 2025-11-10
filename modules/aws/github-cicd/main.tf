# GitHub OIDC Provider
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # https://github.blog/changelog/2023-06-27-github-actions-update-on-oidc-integration-with-aws/
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]
}

# Compute the list of repositories (support both old and new formats)
locals {
  # If repositories list is provided, use it; otherwise fall back to old variables
  repos_list = var.repositories

  # Generate the list of repo patterns for StringLike condition
  repo_patterns = [for repo in local.repos_list : "repo:${repo}:*"]
}

# IAM Role for GitHub Actions
resource "aws_iam_role" "github_actions_cicd" {
  name = "github-actions-cicd-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = local.repo_patterns
          }
        }
      }
    ]
  })
}

# ECR 權限
resource "aws_iam_role_policy" "ecr_policy" {
  name = "github-actions-ecr-policy"
  role = aws_iam_role.github_actions_cicd.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = "*"
      }
    ]
  })
}

# ECS 權限
resource "aws_iam_role_policy" "ecs_policy" {
  name = "github-actions-ecs-policy"
  role = aws_iam_role.github_actions_cicd.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition",
          "ecs:DescribeServices",
          "ecs:UpdateService"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM PassRole 權限（允許傳遞 ECS 角色）
resource "aws_iam_role_policy" "pass_role_policy" {
  name = "github-actions-pass-role-policy"
  role = aws_iam_role.github_actions_cicd.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = [
          "arn:aws:iam::*:role/*ecs-execution-role",
          "arn:aws:iam::*:role/*ecs-task-role"
        ]
      }
    ]
  })
}

# Terraform 權限（如果需要）
resource "aws_iam_role_policy" "terraform_policy" {
  count = var.enable_terraform_permissions ? 1 : 0
  name  = "github-actions-terraform-policy"
  role  = aws_iam_role.github_actions_cicd.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:*",
          "dynamodb:*",
          "ec2:*",
          "rds:*",
          "vpc:*",
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies"
        ]
        Resource = "*"
      },
      {
        Effect = "Deny"
        Action = [
          "iam:*",
          "organizations:*",
          "account:*",
          "billing:*",
          "aws-portal:*",
          "budgets:*",
          "cur:*",
          "support:*"
        ]
        Resource = "*"
      }
    ]
  })
}
