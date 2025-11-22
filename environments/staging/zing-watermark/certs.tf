# mTLS Certificates for ECS Server
# Store server certificates in Secrets Manager for ECS to accept TEE connections

# Use existing secret (created via create-cert-secret.sh script)
data "aws_secretsmanager_secret" "ecs_server_cert" {
  name = "ecs-server-mtls-cert"
}

# Update secret version if certificates exist locally
resource "aws_secretsmanager_secret_version" "ecs_server_cert" {
  secret_id = data.aws_secretsmanager_secret.ecs_server_cert.id

  secret_string = jsonencode({
    server_cert = file("${path.module}/certs/ecs-server.crt")
    server_key  = file("${path.module}/certs/ecs-server.key")
    ca_cert     = file("${path.module}/certs/ecs-ca.crt")
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# Output the secret ARN for use in terraform.tfvars
output "ecs_server_cert_secret_arn" {
  description = "ARN of the ECS server certificate secret"
  value       = data.aws_secretsmanager_secret.ecs_server_cert.arn
}

