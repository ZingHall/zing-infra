# Nitro Enclave Module Examples

This document provides practical examples of using the Nitro Enclave module in different scenarios.

## Example 1: Basic Production Deployment

```hcl
# Get VPC data
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "terraform-zing-production"
    key    = "network.tfstate"
    region = "ap-northeast-1"
  }
}

# S3 bucket for EIF files
resource "aws_s3_bucket" "enclave_artifacts" {
  bucket = "zing-enclave-artifacts-prod"
}

resource "aws_s3_bucket_versioning" "enclave_artifacts" {
  bucket = aws_s3_bucket.enclave_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Nitro Enclave deployment
module "nautilus_enclave" {
  source = "../../../modules/aws/enclave"

  name    = "nautilus-watermark-prod"
  vpc_id  = data.terraform_remote_state.network.outputs.vpc_id
  subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids

  s3_bucket_name = aws_s3_bucket.enclave_artifacts.bucket
  s3_bucket_arn  = aws_s3_bucket.enclave_artifacts.arn
  eif_version    = var.enclave_version  # Set via terraform.tfvars or CI/CD
  eif_path       = "eif/production"

  instance_type = "m5.xlarge"
  min_size      = 2
  max_size      = 5
  desired_capacity = 2

  enclave_cpu_count  = 2
  enclave_memory_mb  = 512
  enclave_port       = 3000
  enclave_init_port  = 3001

  allowed_cidr_blocks = [
    data.terraform_remote_state.network.outputs.vpc_cidr_block
  ]

  secrets_arns = [
    aws_secretsmanager_secret.enclave_secrets.arn
  ]

  enable_auto_scaling = true
  target_cpu_utilization = 70
  target_memory_utilization = 80

  health_check_grace_period = 300

  tags = {
    Environment = "production"
    Application = "nautilus-watermark"
    ManagedBy   = "terraform"
  }
}

# Secrets Manager for enclave configuration
resource "aws_secretsmanager_secret" "enclave_secrets" {
  name = "nautilus-enclave-secrets"
}
```

## Example 2: Staging Environment with ALB

```hcl
# Get network state
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "terraform-zing-staging"
    key    = "network.tfstate"
    region = "ap-northeast-1"
  }
}

# Enclave deployment
module "nautilus_enclave_staging" {
  source = "../../../modules/aws/enclave"

  name    = "nautilus-watermark-staging"
  vpc_id  = data.terraform_remote_state.network.outputs.vpc_id
  subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids

  s3_bucket_name = "zing-enclave-artifacts-staging"
  s3_bucket_arn  = "arn:aws:s3:::zing-enclave-artifacts-staging"
  eif_version    = "latest"  # Use latest for staging
  eif_path       = "eif/staging"

  instance_type = "m5.large"  # Smaller instance for staging
  min_size      = 1
  max_size      = 2
  desired_capacity = 1

  enable_public_ip = false  # Private subnets

  tags = {
    Environment = "staging"
    Application = "nautilus-watermark"
  }
}

# ALB for load balancing
module "alb" {
  source = "../../../modules/aws/https-alb"

  name    = "nautilus-enclave-alb"
  vpc_id  = data.terraform_remote_state.network.outputs.vpc_id
  subnets = data.terraform_remote_state.network.outputs.public_subnet_ids

  certificate_arn = aws_acm_certificate.enclave.arn

  listeners = [
    {
      port     = 443
      protocol = "HTTPS"
      default_action = {
        type             = "forward"
        target_group_key = "enclave"
      }
    }
  ]

  target_groups = [
    {
      key             = "enclave"
      name            = "nautilus-enclave"
      port            = 3000
      protocol        = "HTTP"
      health_check    = {
        enabled             = true
        healthy_threshold   = 2
        unhealthy_threshold = 3
        timeout             = 5
        interval            = 30
        path                = "/health_check"
        matcher             = "200"
      }
    }
  ]

  tags = {
    Environment = "staging"
  }
}

# Attach ASG to ALB target group
resource "aws_autoscaling_attachment" "enclave" {
  autoscaling_group_name = module.nautilus_enclave_staging.autoscaling_group_id
  lb_target_group_arn    = module.alb.target_group_arns["enclave"]
}

# ACM Certificate
resource "aws_acm_certificate" "enclave" {
  domain_name       = "enclave.staging.zing.you"
  validation_method = "DNS"

  tags = {
    Environment = "staging"
  }
}
```

## Example 3: Multi-Region Deployment

```hcl
# Primary region (ap-northeast-1)
module "nautilus_enclave_primary" {
  source = "../../../modules/aws/enclave"

  providers = {
    aws = aws.primary
  }

  name    = "nautilus-watermark-primary"
  vpc_id  = var.primary_vpc_id
  subnet_ids = var.primary_subnet_ids

  s3_bucket_name = "zing-enclave-artifacts-primary"
  s3_bucket_arn  = "arn:aws:s3:::zing-enclave-artifacts-primary"
  eif_version    = var.enclave_version
  eif_path       = "eif/production"

  min_size = 2
  max_size = 5
  desired_capacity = 2

  tags = {
    Environment = "production"
    Region      = "primary"
  }
}

# Secondary region (us-east-1)
module "nautilus_enclave_secondary" {
  source = "../../../modules/aws/enclave"

  providers = {
    aws = aws.secondary
  }

  name    = "nautilus-watermark-secondary"
  vpc_id  = var.secondary_vpc_id
  subnet_ids = var.secondary_subnet_ids

  s3_bucket_name = "zing-enclave-artifacts-secondary"
  s3_bucket_arn  = "arn:aws:s3:::zing-enclave-artifacts-secondary"
  eif_version    = var.enclave_version
  eif_path       = "eif/production"

  min_size = 1
  max_size = 3
  desired_capacity = 1

  tags = {
    Environment = "production"
    Region      = "secondary"
  }
}
```

## Example 4: With Custom User Data

```hcl
module "nautilus_enclave" {
  source = "../../../modules/aws/enclave"

  name    = "nautilus-watermark"
  vpc_id  = var.vpc_id
  subnet_ids = var.subnet_ids

  s3_bucket_name = "zing-enclave-artifacts"
  s3_bucket_arn  = "arn:aws:s3:::zing-enclave-artifacts"
  eif_version    = var.enclave_version

  # Custom user data to install additional tools
  user_data_extra = <<-EOF
    # Install custom monitoring agent
    yum install -y custom-monitoring-agent
    systemctl enable custom-monitoring-agent
    systemctl start custom-monitoring-agent

    # Configure custom settings
    echo "CUSTOM_SETTING=value" >> /etc/environment
  EOF

  tags = {
    Environment = "production"
  }
}
```

## Example 5: With Route53 DNS

```hcl
# Get hosted zone
data "aws_route53_zone" "main" {
  name = "zing.you"
}

module "nautilus_enclave" {
  source = "../../../modules/aws/enclave"

  name    = "nautilus-watermark"
  vpc_id  = var.vpc_id
  subnet_ids = var.subnet_ids

  s3_bucket_name = "zing-enclave-artifacts"
  s3_bucket_arn  = "arn:aws:s3:::zing-enclave-artifacts"
  eif_version    = var.enclave_version

  # DNS configuration
  create_dns_record = true
  route53_zone_id   = data.aws_route53_zone.main.zone_id
  dns_name          = "enclave.zing.you"
  dns_ttl           = 300

  tags = {
    Environment = "production"
  }
}

# Note: DNS record will need to be updated manually with actual IPs
# or via external script that queries the ASG instances
```

## Example 6: Cost-Optimized with Spot Instances

```hcl
# Launch template with spot instances
resource "aws_launch_template" "enclave_spot" {
  name_prefix   = "nautilus-enclave-spot-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "m5.xlarge"

  instance_market_options {
    market_type = "spot"
    spot_options {
      max_price = "0.10"  # Maximum price per hour
    }
  }

  # ... other configuration
}

# Use spot instances in ASG
resource "aws_autoscaling_group" "enclave_spot" {
  name = "nautilus-enclave-spot-asg"

  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.enclave_spot.id
        version            = "$Latest"
      }
    }

    instances_distribution {
      on_demand_percentage_above_base_capacity = 0
      spot_allocation_strategy                  = "capacity-optimized"
    }
  }

  # ... other configuration
}
```

## Example 7: CI/CD Integration

### Terraform Variables

```hcl
# terraform.tfvars
enclave_version = "abc123"  # Updated by CI/CD
```

### GitHub Actions Workflow

```yaml
name: Deploy Enclave

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build EIF
        run: |
          cd nautilus-watermark-service
          make ENCLAVE_APP=zing-watermark

      - name: Upload to S3
        env:
          COMMIT_SHA: ${{ github.sha }}
        run: |
          aws s3 cp nautilus-watermark-service/out/nitro.eif \
            s3://zing-enclave-artifacts/eif/production/nitro-${COMMIT_SHA:0:7}.eif

      - name: Update Terraform
        env:
          COMMIT_SHA: ${{ github.sha }}
        run: |
          cd zing-infra/environments/production
          sed -i "s/eif_version = \".*\"/eif_version = \"${COMMIT_SHA:0:7}\"/" enclave.tf

      - name: Apply Terraform
        run: |
          cd zing-infra/environments/production
          terraform init
          terraform apply -auto-approve
```

## Example 8: Monitoring and Alarms

```hcl
module "nautilus_enclave" {
  source = "../../../modules/aws/enclave"

  # ... configuration
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "enclave_cpu_high" {
  alarm_name          = "nautilus-enclave-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "This metric monitors enclave CPU utilization"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    AutoScalingGroupName = module.nautilus_enclave.autoscaling_group_name
  }
}

resource "aws_cloudwatch_metric_alarm" "enclave_health" {
  alarm_name          = "nautilus-enclave-health"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "GroupInServiceInstances"
  namespace           = "AWS/AutoScaling"
  period              = 60
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "This metric monitors enclave instance health"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    AutoScalingGroupName = module.nautilus_enclave.autoscaling_group_name
  }
}

resource "aws_sns_topic" "alerts" {
  name = "nautilus-enclave-alerts"
}
```

## Best Practices

1. **Version Management**: Always use commit SHAs or version tags for EIF files
2. **Multi-AZ**: Deploy across multiple availability zones for high availability
3. **Monitoring**: Set up CloudWatch alarms for critical metrics
4. **Backup**: Keep multiple versions of EIF files in S3
5. **Security**: Use encrypted S3 buckets and IAM roles with least privilege
6. **Testing**: Test deployments in staging before production
7. **Rollback**: Keep previous EIF versions for quick rollback

