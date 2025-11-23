# mTLS Client Certificates for TEE (Nitro Enclave)
# Reference existing secret in Secrets Manager for TEE to connect to watermark service
#
# The secret is already deployed to Secrets Manager with ARN:
# arn:aws:secretsmanager:ap-northeast-1:287767576800:secret:nautilus-enclave-mtls-client-cert-uFesgM
#
# This Terraform configuration only references the existing secret for IAM permissions.
# The secret content is managed externally and should not be updated by Terraform.

# Reference existing secret (secret already exists in Secrets Manager)
data "aws_secretsmanager_secret" "mtls_client_cert" {
  name = "nautilus-enclave-mtls-client-cert"
}

# Note: We do NOT create or update the secret version here because:
# 1. The secret already exists in Secrets Manager
# 2. The secret content is managed externally (manually or via CI/CD)
# 3. We only need to reference it for IAM permissions in main.tf
#
# If you need to update the secret content, use:
#   aws secretsmanager update-secret \
#     --secret-id nautilus-enclave-mtls-client-cert \
#     --secret-string file://zing-infra/environments/staging/zing-watermark/certs/client-cert.json
#
# Or use the script: zing-infra/environments/staging/zing-watermark/create-cert-secret.sh

# Note: Secret ARN is output in outputs.tf as mtls_client_secret_arn

