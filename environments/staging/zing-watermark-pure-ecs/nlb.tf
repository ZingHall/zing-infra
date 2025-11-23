# Network Load Balancer for Watermark Service (mTLS Passthrough)
# NLB uses TCP passthrough to preserve end-to-end mTLS encryption
#
# Note: NLB (Layer 4) does NOT use security groups - access control is via:
# - Subnet routing (internal NLB only accessible within VPC)
# - ECS Security Group (controls access to ECS tasks)
# - VPC network ACLs (if configured)

# Network Load Balancer (Internal)
resource "aws_lb" "watermark_nlb" {
  name               = "zing-watermark-nlb"
  internal           = true # Internal NLB, only accessible within VPC
  load_balancer_type = "network"
  subnets            = data.terraform_remote_state.network.outputs.private_subnet_ids

  enable_deletion_protection       = false
  enable_cross_zone_load_balancing = true # Distribute traffic across AZs

  tags = {
    Name        = "zing-watermark-nlb"
    application = "zing-watermark"
    purpose     = "mtls-load-balancer"
    region      = "ap-northeast-1"
  }
}

# Target Group (TCP - preserves mTLS)
resource "aws_lb_target_group" "watermark" {
  name        = "zing-watermark-tg"
  port        = 8080
  protocol    = "TCP"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id
  target_type = "ip" # Fargate uses IP mode

  # Health check (TCP-based)
  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = 8080
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  # Deregistration delay (graceful shutdown)
  deregistration_delay = 30

  # Preserve client IP (important for mTLS)
  preserve_client_ip = false # NLB doesn't support this for IP targets

  tags = {
    Name        = "zing-watermark-tg"
    application = "zing-watermark"
    purpose     = "target-group"
    region      = "ap-northeast-1"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Listener (TCP - passthrough for mTLS)
resource "aws_lb_listener" "watermark" {
  load_balancer_arn = aws_lb.watermark_nlb.arn
  port              = 8080
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.watermark.arn
  }

  tags = {
    Name        = "zing-watermark-listener"
    application = "zing-watermark"
    purpose     = "nlb-listener"
  }
}

