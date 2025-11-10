# Usage Examples

## Example 1: Multiple repositories from same organization

```hcl
module "github_cicd_single_org" {
  source = "../../../modules/aws/github-cicd"

  repositories = [
    "jastron-tech/*" # All repos in jastron-tech org
  ]
}

# Example 2: Multiple repositories from different owners
module "github_cicd_multi_org" {
  source = "../../../modules/aws/github-cicd"

  repositories = [
    "jastron-tech/backend-api",
    "jastron-tech/frontend-app",
    "another-org/shared-library",
    "third-org/*" # All repos in third-org
  ]

  enable_terraform_permissions = true
}

```

## Example 4: Specific repositories only

```hcl
module "github_cicd" {
  source = "../../../modules/aws/github-cicd"

  repositories = [
    "company-a/production-app",
    "company-b/staging-app"
  ]
}
```

