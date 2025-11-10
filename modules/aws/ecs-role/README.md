# ECS Role Module

Create IAM roles for ECS tasks. This module creates both execution and task roles needed for ECS task definitions.

## Overview

This module creates two IAM roles:

1. **Execution Role** - Used by ECS to:
   - Pull container images from ECR
   - Write logs to CloudWatch
   - Access secrets from Secrets Manager/SSM

2. **Task Role** - Used by your application to:
   - Access AWS services (S3, DynamoDB, etc.)
   - Write logs to CloudWatch
   - Custom permissions for your app

## Use with CI/CD

These roles are meant to be referenced in task definitions created by CI/CD:

```yaml
# In your CI/CD pipeline (GitHub Actions, etc.)
aws ecs register-task-definition \
  --family my-task \
  --execution-role-arn $EXECUTION_ROLE_ARN \  # From this module
  --task-role-arn $TASK_ROLE_ARN \             # From this module
  ...
```

## Usage

### Basic Example

```hcl
module "app_roles" {
  source = "../../../modules/aws/ecs-role"

  name = "my-app"

  tags = {
    Environment = "production"
    Application = "my-app"
  }
}

# Use in task definition (CI/CD)
# execution_role_arn = module.app_roles.execution_role_arn
# task_role_arn      = module.app_roles.task_role_arn
```

### With Secrets Access

```hcl
module "app_roles" {
  source = "../../../modules/aws/ecs-role"

  name = "my-app"

  # Enable secrets access
  enable_secrets_access = true
  
  secrets_arns = [
    "arn:aws:secretsmanager:us-east-1:123456789:secret:my-app/*",
  ]
  
  ssm_parameter_arns = [
    "arn:aws:ssm:us-east-1:123456789:parameter/my-app/*",
  ]

  # Specify log group for precise permissions
  log_group_arn = aws_cloudwatch_log_group.app.arn

  tags = {
    Environment = "production"
  }
}
```

### With Custom Policies

```hcl
module "app_roles" {
  source = "../../../modules/aws/ecs-role"

  name = "my-app"

  # Custom execution role policies (for pulling from private registries, etc.)
  execution_role_policies = {
    ecr-cross-account = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "ecr:GetAuthorizationToken",
            "ecr:BatchCheckLayerAvailability",
            "ecr:GetDownloadUrlForLayer",
            "ecr:BatchGetImage"
          ]
          Resource = "arn:aws:ecr:us-east-1:987654321:repository/shared-images/*"
        }
      ]
    })
  }

  # Custom task role policies (for app permissions)
  task_role_policies = {
    s3-access = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "s3:GetObject",
            "s3:PutObject",
            "s3:DeleteObject"
          ]
          Resource = "arn:aws:s3:::my-bucket/*"
        }
      ]
    })
    
    dynamodb-access = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "dynamodb:GetItem",
            "dynamodb:PutItem",
            "dynamodb:Query",
            "dynamodb:Scan"
          ]
          Resource = "arn:aws:dynamodb:us-east-1:123456789:table/my-table"
        }
      ]
    })
  }

  tags = {
    Environment = "production"
  }
}
```

### Multiple Roles for Different Tasks

```hcl
# API task roles
module "api_roles" {
  source = "../../../modules/aws/ecs-role"

  name = "api"

  enable_secrets_access = true
  secrets_arns = ["arn:aws:secretsmanager:*:*:secret:api-*"]

  task_role_policies = {
    s3-read = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect   = "Allow"
          Action   = ["s3:GetObject"]
          Resource = "arn:aws:s3:::my-bucket/*"
        }
      ]
    })
  }

  tags = {
    Service = "api"
  }
}

# Worker task roles
module "worker_roles" {
  source = "../../../modules/aws/ecs-role"

  name = "worker"

  enable_secrets_access = true
  secrets_arns = ["arn:aws:secretsmanager:*:*:secret:worker-*"]

  task_role_policies = {
    s3-write = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "s3:GetObject",
            "s3:PutObject"
          ]
          Resource = "arn:aws:s3:::my-bucket/*"
        }
      ]
    })
    
    sqs-access = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "sqs:ReceiveMessage",
            "sqs:DeleteMessage",
            "sqs:GetQueueAttributes"
          ]
          Resource = "arn:aws:sqs:us-east-1:123456789:my-queue"
        }
      ]
    })
  }

  tags = {
    Service = "worker"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name prefix for IAM roles | string | - | yes |
| enable_secrets_access | Enable Secrets Manager/SSM access | bool | false | no |
| secrets_arns | Secrets Manager ARNs | list(string) | ["*"] | no |
| ssm_parameter_arns | SSM Parameter ARNs | list(string) | ["*"] | no |
| log_group_arn | CloudWatch log group ARN | string | "" | no |
| execution_role_policies | Custom execution policies | map(string) | {} | no |
| task_role_policies | Custom task policies | map(string) | {} | no |
| tags | Resource tags | map(string) | {} | no |

## Outputs

| Name | Description |
|------|-------------|
| execution_role_arn | Execution role ARN |
| execution_role_name | Execution role name |
| execution_role_id | Execution role ID |
| task_role_arn | Task role ARN |
| task_role_name | Task role name |
| task_role_id | Task role ID |

## Default Permissions

### Execution Role
- ✅ Pull images from ECR
- ✅ Write logs to CloudWatch
- ✅ Access Secrets Manager (if enabled)
- ✅ Access SSM Parameter Store (if enabled)

### Task Role
- ✅ Write logs to CloudWatch
- ✅ Custom policies you add

## Integration with CI/CD

### GitHub Actions Example

```yaml
name: Deploy ECS Task

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: us-east-1
      
      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v1
      
      - name: Build and push image
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          ECR_REPOSITORY: my-app
          IMAGE_TAG: ${{ github.sha }}
        run: |
          docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
      
      - name: Register task definition
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          ECR_REPOSITORY: my-app
          IMAGE_TAG: ${{ github.sha }}
        run: |
          aws ecs register-task-definition \
            --family my-app \
            --requires-compatibilities FARGATE \
            --network-mode awsvpc \
            --cpu 512 \
            --memory 1024 \
            --execution-role-arn ${{ secrets.EXECUTION_ROLE_ARN }} \
            --task-role-arn ${{ secrets.TASK_ROLE_ARN }} \
            --container-definitions '[{
              "name": "app",
              "image": "'$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG'",
              "essential": true,
              "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                  "awslogs-group": "/aws/ecs/my-app",
                  "awslogs-region": "us-east-1",
                  "awslogs-stream-prefix": "ecs"
                }
              }
            }]'
```

### Store Role ARNs in GitHub Secrets

After creating roles with Terraform:

```bash
# Get role ARNs from Terraform
EXECUTION_ROLE_ARN=$(terraform output -raw app_roles_execution_role_arn)
TASK_ROLE_ARN=$(terraform output -raw app_roles_task_role_arn)

# Add to GitHub secrets
gh secret set EXECUTION_ROLE_ARN -b"$EXECUTION_ROLE_ARN"
gh secret set TASK_ROLE_ARN -b"$TASK_ROLE_ARN"
```

## Common Patterns

### Read-Only S3 Access

```hcl
task_role_policies = {
  s3-readonly = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::my-bucket",
          "arn:aws:s3:::my-bucket/*"
        ]
      }
    ]
  })
}
```

### DynamoDB Table Access

```hcl
task_role_policies = {
  dynamodb = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = "arn:aws:dynamodb:${var.region}:${var.account_id}:table/my-table"
      }
    ]
  })
}
```

### SQS Queue Access

```hcl
task_role_policies = {
  sqs = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = "arn:aws:sqs:${var.region}:${var.account_id}:my-queue"
      }
    ]
  })
}
```

### SNS Publish

```hcl
task_role_policies = {
  sns = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = "arn:aws:sns:${var.region}:${var.account_id}:my-topic"
      }
    ]
  })
}
```

## Best Practices

1. **Principle of Least Privilege** - Only grant permissions your task needs
2. **Separate Roles** - Create different roles for different tasks
3. **Specific ARNs** - Specify exact resource ARNs instead of using wildcards
4. **Enable Secrets Access** - Only when needed
5. **Use Log Groups** - Specify log group ARN for precise permissions
6. **Tag Roles** - Use tags for cost tracking and organization

## Related Modules

- **`ecs-cluster`** - ECS cluster management
- **`ecs-service`** - Long-running ECS services
- **`ecs-task`** - One-off manual tasks
- **`ecs-cron-job`** - Scheduled cron jobs

---

**Perfect for managing ECS IAM roles!** 🔐

