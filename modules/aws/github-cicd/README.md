# GitHub Actions CICD Module

This module sets up GitHub Actions OIDC integration with AWS, allowing GitHub Actions workflows to authenticate with AWS without storing long-lived credentials.

## Features

- GitHub OIDC Provider setup
- IAM Role for GitHub Actions with least-privilege permissions
- Support for multiple repositories
- ECR push/pull permissions
- ECS deployment permissions
- Optional Terraform permissions

## Usage

### Single Repository (Legacy)

```hcl
module "github_cicd" {
  source     = "../../../modules/aws/github-cicd"
  repo_owner = "jastron-tech"
  repo_name  = "*"
}
```

### Multiple Repositories (Recommended)

```hcl
module "github_cicd" {
  source = "../../../modules/aws/github-cicd"
  
  repositories = [
    "jastron-tech/*",
    "another-org/specific-repo",
    "third-org/another-repo"
  ]
}
```

### With Terraform Permissions

```hcl
module "github_cicd" {
  source = "../../../modules/aws/github-cicd"
  
  repositories = [
    "jastron-tech/*"
  ]
  
  enable_terraform_permissions = true
}
```

## Repository Format

Repositories should be specified in `owner/repo` format:
- `jastron-tech/*` - All repositories in the jastron-tech organization
- `jastron-tech/my-app` - Specific repository only
- Multiple entries are supported for fine-grained control

## GitHub Actions Workflow Example

```yaml
name: Deploy to AWS

on:
  push:
    branches: [main]

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ap-northeast-1
      
      - name: Login to ECR
        run: |
          aws ecr get-login-password --region ap-northeast-1 | \
          docker login --username AWS --password-stdin $ECR_REGISTRY
      
      - name: Build and push
        run: |
          docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| repo_owner | (Deprecated) GitHub repository owner | string | "" | no |
| repo_name | (Deprecated) GitHub repository name | string | "" | no |
| repositories | List of GitHub repositories in 'owner/repo' format | list(string) | [] | no* |
| enable_terraform_permissions | Enable Terraform state management permissions | bool | false | no |

*Either `repositories` or both `repo_owner` and `repo_name` must be provided.

## Outputs

| Name | Description |
|------|-------------|
| role_arn | GitHub Actions IAM Role ARN (use in GitHub secrets) |
| role_id | GitHub Actions IAM Role ID |
| role_name | GitHub Actions IAM Role Name |
| oidc_provider_arn | GitHub OIDC Provider ARN |
| allowed_repositories | List of allowed GitHub repositories |

## IAM Permissions

The module creates an IAM role with the following permissions:

### ECR (Always enabled)
- Push and pull Docker images
- Get authorization token

### ECS (Always enabled)
- Describe and register task definitions
- Update services

### IAM Pass Role (Always enabled)
- Pass ECS execution and task roles

### Terraform (Optional)
- S3, DynamoDB, EC2, RDS, VPC operations
- Read-only IAM operations
- Explicit deny on sensitive operations (billing, organizations, etc.)

## Migration from Legacy Variables

If you're currently using `repo_owner` and `repo_name`:

**Before:**
```hcl
module "github_cicd" {
  source     = "../../../modules/aws/github-cicd"
  repo_owner = "jastron-tech"
  repo_name  = "*"
}
```

**After:**
```hcl
module "github_cicd" {
  source = "../../../modules/aws/github-cicd"
  
  repositories = [
    "jastron-tech/*"
  ]
}
```

The old variables will continue to work but are deprecated.

## Security Notes

1. Always use the principle of least privilege - only grant access to the specific repositories that need it
2. Consider using specific repository names instead of wildcards when possible
3. The Terraform permissions are broad and should only be enabled for trusted repositories
4. Review the IAM policies regularly and adjust based on your needs

