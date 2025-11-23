# mTLS Client Certificates for TEE (Nitro Enclave)
# Store client certificates in Secrets Manager for TEE to connect to watermark service
#
# The certificates are read from zing-watermark/certs directory
# The client-cert.json file contains client_cert, client_key, and ca_cert
# Uses tee-client.crt and tee-client.key (TEE-specific client certificates)
#
# To generate client-cert.json:
#   cd zing-infra/environments/staging/zing-watermark/certs && node create-client-cert-json.js
#   (Requires tee-client.crt, tee-client.key, and ecs-ca.crt files)

# Use existing secret or create new one
data "aws_secretsmanager_secret" "mtls_client_cert" {
  count = var.create_mtls_client_secret ? 0 : 1
  name  = "nautilus-enclave-mtls-client-cert"
}

# Create secret if it doesn't exist
resource "aws_secretsmanager_secret" "mtls_client_cert" {
  count = var.create_mtls_client_secret ? 1 : 0
  name  = "nautilus-enclave-mtls-client-cert"

  description = "mTLS client certificates for TEE (Nitro Enclave) to connect to watermark service"

  tags = merge({
    Purpose     = "mTLS"
    Role        = "client"
    Environment = "staging"
    Service     = "nautilus-enclave"
  })
}

# Update secret version with certificates from zing-watermark/certs
# Read the JSON file that contains client certificates
resource "aws_secretsmanager_secret_version" "mtls_client_cert" {
  secret_id = var.create_mtls_client_secret ? aws_secretsmanager_secret.mtls_client_cert[0].id : data.aws_secretsmanager_secret.mtls_client_cert[0].id

  # Read certificates from zing-watermark/certs directory
  # The client-cert.json file contains client_cert, client_key, and ca_cert
  # Uses tee-client.crt and tee-client.key (TEE-specific client certificates)
  # Path: ../zing-watermark/certs/client-cert.json
  # Note: If the file doesn't exist, you may need to create it first
  #   The certificates should be in zing-infra/environments/staging/zing-watermark/certs/
  secret_string = file("${path.module}/../zing-watermark/certs/client-cert.json")

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# Note: Secret ARN is output in outputs.tf as mtls_client_secret_arn

