# GitHub CICD Module - Quick Start

## Basic Usage

### Single Organization (All Repos)
```hcl
module "github_cicd" {
  source = "../../../modules/aws/github-cicd"
  
  repositories = [
    "jastron-tech/*"
  ]
}
```

### Multiple Organizations
```hcl
module "github_cicd" {
  source = "../../../modules/aws/github-cicd"
  
  repositories = [
    "jastron-tech/*",
    "company-b/app-backend",
    "company-c/*"
  ]
}
```

### Specific Repositories Only
```hcl
module "github_cicd" {
  source = "../../../modules/aws/github-cicd"
  
  repositories = [
    "jastron-tech/production-app",
    "jastron-tech/staging-app"
  ]
}
```

## Get Role ARN for GitHub Secrets

After applying:
```bash
cd environments/nextlink-staging/cicd
terraform output github_actions_cicd_role_arn
```

Copy this value to your GitHub repository secrets as `AWS_ROLE_ARN`.

## GitHub Actions Workflow

```yaml
name: Deploy
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
      
      - name: Configure AWS
        uses: aws-actions/configure-aws-credentials@v2
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ap-northeast-1
      
      - name: Deploy
        run: |
          # Your deployment commands here
```

## Verify Setup

```bash
# Check allowed repositories
terraform output allowed_repositories

# Validate configuration
terraform validate

# Preview changes
terraform plan
```

## Common Patterns

| Pattern | Description |
|---------|-------------|
| `owner/*` | All repos in organization |
| `owner/app-*` | All repos starting with "app-" |
| `owner/repo` | Specific repository only |
| Multiple entries | Different orgs/repos |

## Troubleshooting

**Error: "Not authorized to perform sts:AssumeRoleWithWebIdentity"**
- Check repository name matches allowed list
- Verify `permissions: id-token: write` in workflow
- Confirm role ARN is correct in GitHub secrets

**Want to add more repos?**
Just add them to the `repositories` list and run `terraform apply`.

