# mTLS Certificates for ECS Server (Pure ECS - Fargate)
# Store server certificates in Secrets Manager for ECS to accept TEE connections

# Copy certificates from zing-watermark/certs directory
# The certificates are already generated and stored in JSON format

# Use existing secret or create new one
data "aws_secretsmanager_secret" "ecs_server_cert" {
  count = var.create_mtls_secret ? 0 : 1
  name  = "ecs-server-mtls-cert"
}

# Create secret if it doesn't exist
resource "aws_secretsmanager_secret" "ecs_server_cert" {
  count = var.create_mtls_secret ? 1 : 0
  name  = "ecs-server-mtls-cert-pure-ecs"

  description = "mTLS server certificates for ECS watermark service (pure-ecs cluster in ap-northeast-1)"

  tags = merge(var.tags, {
    Purpose = "mTLS"
    Role    = "server"
    Cluster = "zing-watermark-pure-ecs"
  })
}

# Update secret version with certificates from zing-watermark/certs
# Read the JSON file that contains all certificates
resource "aws_secretsmanager_secret_version" "ecs_server_cert" {
  secret_id = var.create_mtls_secret ? aws_secretsmanager_secret.ecs_server_cert[0].id : data.aws_secretsmanager_secret.ecs_server_cert[0].id

  # Read certificates from zing-watermark/certs directory
  # The ecs-server-cert.json file contains server_cert, server_key, and ca_cert
  # Path: ../zing-watermark/certs/ecs-server-cert.json
  secret_string = file("${path.module}/../zing-watermark/certs/ecs-server-cert.json")

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# Note: Secret ARN is output in outputs.tf as mtls_secret_arn

