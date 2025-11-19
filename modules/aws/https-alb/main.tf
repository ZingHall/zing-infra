# Application Load Balancer
resource "aws_alb" "this" {
  name            = "${var.name}-alb"
  internal        = var.internal
  security_groups = [aws_security_group.alb.id]
  subnets         = var.subnet_ids

  access_logs {
    enabled = var.access_log_bucket != ""
    bucket  = var.access_log_bucket
    prefix  = var.access_log_prefix != "" ? var.access_log_prefix : "${var.name}-alb-logs"
  }

  tags = var.tags
}

# ALB Security Group
resource "aws_security_group" "alb" {
  name        = "${var.name}-alb-sg"
  description = "ALB security group for ${var.name}"
  vpc_id      = var.vpc_id

  # HTTPS ingress
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.ingress_cidr_blocks
    description = "HTTPS ingress"
  }

  # HTTP ingress (for redirect)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.http_redirect ? var.ingress_cidr_blocks : []
    description = "HTTP ingress for redirect"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = var.tags
}

# HTTP to HTTPS redirect listener
resource "aws_alb_listener" "http" {
  count             = var.http_redirect ? 1 : 0
  load_balancer_arn = aws_alb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = var.tags
}

# HTTPS listener with default 404 response
resource "aws_alb_listener" "https" {
  load_balancer_arn = aws_alb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "application/json"
      message_body = jsonencode({
        message = "404 Not Found - No service configured"
      })
      status_code = "404"
    }
  }

  tags = var.tags
}

# Additional SSL certificates (for multi-domain support)
resource "aws_alb_listener_certificate" "additional" {
  for_each        = toset(var.additional_certificate_arns)
  listener_arn    = aws_alb_listener.https.arn
  certificate_arn = each.value
}

# Target Groups for each service
resource "aws_alb_target_group" "services" {
  for_each = { for svc in var.services : svc.name => svc }

  name_prefix = substr("${var.name}-${each.value.name}", 0, 6)
  port        = each.value.port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = each.value.target_type # "ip" for ECS Fargate, "instance" for EC2

  health_check {
    enabled             = true
    path                = each.value.health_check_path
    protocol            = "HTTP"
    matcher             = each.value.health_check_matcher
    interval            = each.value.health_check_interval
    timeout             = each.value.health_check_timeout
    healthy_threshold   = each.value.health_check_healthy_threshold
    unhealthy_threshold = each.value.health_check_unhealthy_threshold
  }

  deregistration_delay = each.value.deregistration_delay

  dynamic "stickiness" {
    for_each = each.value.stickiness_enabled ? [1] : []
    content {
      enabled         = true
      type            = "lb_cookie"
      cookie_duration = each.value.stickiness_duration
    }
  }

  tags = merge(var.tags, {
    Service = each.value.name
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Listener Rules for each service (Host-based routing)
resource "aws_alb_listener_rule" "services" {
  for_each = { for svc in var.services : svc.name => svc }

  listener_arn = aws_alb_listener.https.arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.services[each.key].arn
  }

  condition {
    host_header {
      values = each.value.host_headers
    }
  }

  tags = merge(var.tags, {
    Service = each.value.name
  })
}

