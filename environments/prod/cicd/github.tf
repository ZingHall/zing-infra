module "github_cicd" {
  source = "../../../modules/aws/github-cicd"

  repositories = [
    "ZingHall/*"
  ]

  # Enable Terraform permissions for:
  # 1. S3 access (upload EIF files to zing-enclave-artifacts-* buckets)
  # 2. Terraform backend access (S3 + DynamoDB for state management)
  # 3. EC2/VPC operations (for Auto Scaling Group and Enclave deployment)
  enable_terraform_permissions = true
}
