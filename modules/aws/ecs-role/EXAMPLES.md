# ECS Role Module - Examples

## Example 1: Basic Roles

```hcl
module "app_roles" {
  source = "../../../modules/aws/ecs-role"

  name = "my-app"

  tags = {
    Environment = "production"
    Application = "my-app"
  }
}

# CI/CD uses these ARNs
output "execution_role" {
  value = module.app_roles.execution_role_arn
}

output "task_role" {
  value = module.app_roles.task_role_arn
}
```

## Example 2: With Secrets Access

```hcl
module "api_roles" {
  source = "../../../modules/aws/ecs-role"

  name = "api"

  enable_secrets_access = true
  
  secrets_arns = [
    "arn:aws:secretsmanager:us-east-1:123456789:secret:api/database-*",
    "arn:aws:secretsmanager:us-east-1:123456789:secret:api/api-keys-*",
  ]
  
  ssm_parameter_arns = [
    "arn:aws:ssm:us-east-1:123456789:parameter/api/*",
  ]

  log_group_arn = "/aws/ecs/api"

  tags = {
    Service = "api"
  }
}
```

## Example 3: With S3 Access

```hcl
module "worker_roles" {
  source = "../../../modules/aws/ecs-role"

  name = "worker"

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
          Resource = "arn:aws:s3:::my-data-bucket/*"
        },
        {
          Effect   = "Allow"
          Action   = ["s3:ListBucket"]
          Resource = "arn:aws:s3:::my-data-bucket"
        }
      ]
    })
  }

  tags = {
    Service = "worker"
  }
}
```

## Example 4: Complete Application Setup

```hcl
# API service roles
module "api_roles" {
  source = "../../../modules/aws/ecs-role"

  name = "api"

  enable_secrets_access = true
  secrets_arns = ["arn:aws:secretsmanager:*:*:secret:api-*"]

  task_role_policies = {
    s3-uploads = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "s3:PutObject",
            "s3:GetObject"
          ]
          Resource = "arn:aws:s3:::my-uploads-bucket/*"
        }
      ]
    })
    
    dynamodb-users = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "dynamodb:GetItem",
            "dynamodb:PutItem",
            "dynamodb:UpdateItem",
            "dynamodb:Query"
          ]
          Resource = "arn:aws:dynamodb:us-east-1:123456789:table/users"
        }
      ]
    })
  }

  tags = {
    Service     = "api"
    Environment = "production"
  }
}

# Worker service roles
module "worker_roles" {
  source = "../../../modules/aws/ecs-role"

  name = "worker"

  enable_secrets_access = true
  secrets_arns = ["arn:aws:secretsmanager:*:*:secret:worker-*"]

  task_role_policies = {
    sqs-queue = jsonencode({
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
          Resource = "arn:aws:sqs:us-east-1:123456789:jobs-queue"
        }
      ]
    })
    
    s3-processing = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "s3:GetObject",
            "s3:PutObject",
            "s3:DeleteObject"
          ]
          Resource = "arn:aws:s3:::processing-bucket/*"
        }
      ]
    })
    
    sns-notifications = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect   = "Allow"
          Action   = ["sns:Publish"]
          Resource = "arn:aws:sns:us-east-1:123456789:job-complete"
        }
      ]
    })
  }

  tags = {
    Service     = "worker"
    Environment = "production"
  }
}

# Cron job roles
module "backup_roles" {
  source = "../../../modules/aws/ecs-role"

  name = "cron-backup"

  enable_secrets_access = true
  secrets_arns = ["arn:aws:secretsmanager:*:*:secret:backup-*"]

  task_role_policies = {
    s3-backup = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "s3:PutObject",
            "s3:PutObjectAcl"
          ]
          Resource = "arn:aws:s3:::backups-bucket/*"
        }
      ]
    })
  }

  tags = {
    Service     = "backup"
    Environment = "production"
  }
}
```

## Example 5: Cross-Account ECR Access

```hcl
module "shared_image_roles" {
  source = "../../../modules/aws/ecs-role"

  name = "shared-images"

  execution_role_policies = {
    cross-account-ecr = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "ecr:GetAuthorizationToken"
          ]
          Resource = "*"
        },
        {
          Effect = "Allow"
          Action = [
            "ecr:BatchCheckLayerAvailability",
            "ecr:GetDownloadUrlForLayer",
            "ecr:BatchGetImage"
          ]
          Resource = "arn:aws:ecr:us-east-1:987654321:repository/shared/*"
        }
      ]
    })
  }

  tags = {
    Purpose = "shared-images"
  }
}
```

## Example 6: CI/CD Integration

```hcl
# Terraform creates roles
module "app_roles" {
  source = "../../../modules/aws/ecs-role"

  name = "my-app"

  enable_secrets_access = true
  secrets_arns = ["arn:aws:secretsmanager:*:*:secret:my-app-*"]

  task_role_policies = {
    app-permissions = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "s3:GetObject",
            "s3:PutObject"
          ]
          Resource = "arn:aws:s3:::my-app-data/*"
        }
      ]
    })
  }

  tags = {
    ManagedBy = "terraform"
  }
}

# Export for CI/CD
output "app_execution_role_arn" {
  description = "Execution role ARN for CI/CD"
  value       = module.app_roles.execution_role_arn
}

output "app_task_role_arn" {
  description = "Task role ARN for CI/CD"
  value       = module.app_roles.task_role_arn
}
```

Then in GitHub Actions:

```yaml
- name: Register task definition
  env:
    EXECUTION_ROLE_ARN: ${{ secrets.EXECUTION_ROLE_ARN }}
    TASK_ROLE_ARN: ${{ secrets.TASK_ROLE_ARN }}
  run: |
    aws ecs register-task-definition \
      --family my-app \
      --execution-role-arn $EXECUTION_ROLE_ARN \
      --task-role-arn $TASK_ROLE_ARN \
      ...
```

## Example 7: Multiple Environments

```hcl
locals {
  environments = ["dev", "staging", "prod"]
}

# Create roles for each environment
module "app_roles" {
  for_each = toset(local.environments)

  source = "../../../modules/aws/ecs-role"

  name = "my-app-${each.value}"

  enable_secrets_access = true
  secrets_arns = ["arn:aws:secretsmanager:*:*:secret:my-app-${each.value}-*"]

  task_role_policies = {
    s3-access = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "s3:GetObject",
            "s3:PutObject"
          ]
          Resource = "arn:aws:s3:::my-app-${each.value}-data/*"
        }
      ]
    })
  }

  tags = {
    Environment = each.value
  }
}

# Outputs for each environment
output "execution_role_arns" {
  value = {
    for env in local.environments :
    env => module.app_roles[env].execution_role_arn
  }
}

output "task_role_arns" {
  value = {
    for env in local.environments :
    env => module.app_roles[env].task_role_arn
  }
}
```

## Example 8: Data Pipeline Roles

```hcl
module "pipeline_roles" {
  source = "../../../modules/aws/ecs-role"

  name = "data-pipeline"

  enable_secrets_access = true
  secrets_arns = [
    "arn:aws:secretsmanager:*:*:secret:pipeline/database-*",
    "arn:aws:secretsmanager:*:*:secret:pipeline/api-keys-*"
  ]

  task_role_policies = {
    s3-data-lake = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "s3:GetObject",
            "s3:PutObject",
            "s3:DeleteObject"
          ]
          Resource = [
            "arn:aws:s3:::raw-data-bucket/*",
            "arn:aws:s3:::processed-data-bucket/*"
          ]
        },
        {
          Effect = "Allow"
          Action = ["s3:ListBucket"]
          Resource = [
            "arn:aws:s3:::raw-data-bucket",
            "arn:aws:s3:::processed-data-bucket"
          ]
        }
      ]
    })
    
    glue-catalog = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "glue:GetDatabase",
            "glue:GetTable",
            "glue:GetPartitions",
            "glue:CreateTable",
            "glue:UpdateTable"
          ]
          Resource = "*"
        }
      ]
    })
    
    athena-queries = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "athena:StartQueryExecution",
            "athena:GetQueryExecution",
            "athena:GetQueryResults"
          ]
          Resource = "*"
        }
      ]
    })
  }

  tags = {
    Purpose = "data-pipeline"
  }
}
```

## Best Practices

1. **Use Specific ARNs** - Avoid wildcards when possible
2. **Separate Roles** - Different services get different roles
3. **Environment Isolation** - Different roles per environment
4. **Minimal Permissions** - Only grant what's needed
5. **Tag Everything** - Use tags for organization

---

**Managing ECS IAM roles made easy!** 🔐

