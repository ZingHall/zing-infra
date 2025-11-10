locals {
  port = 5432
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-subnet-group"
  subnet_ids = var.subnet_ids
  tags       = var.tags
}

resource "aws_security_group" "rds" {
  name        = "${var.name}-rds-sg"
  description = "RDS PostgreSQL security group"
  vpc_id      = var.vpc_id

  # 預設不開放任何 ingress，需透過 security group rule 或參數化開放
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

resource "aws_db_parameter_group" "this" {
  family = "postgres17"
  name   = "${var.name}-pg-params-${formatdate("YYYYMMDD-hhmmss", timestamp())}"

  parameter {
    name  = "log_lock_waits"
    value = var.log_lock_waits
  }

  parameter {
    name  = "log_error_verbosity"
    value = var.log_error_verbosity
  }

  parameter {
    name  = "log_min_duration_statement"
    value = var.log_min_duration_statement
  }

  parameter {
    name  = "log_min_error_statement"
    value = var.log_min_error_statement
  }

  parameter {
    name         = "max_connections"
    value        = var.max_connections
    apply_method = "pending-reboot"
  }

  tags = var.tags
}

resource "aws_db_instance" "this" {
  identifier = var.name

  # Engine 設定
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  # Storage 設定
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = var.iops != null ? "io1" : "gp2"
  iops                  = var.iops
  storage_encrypted     = var.storage_encrypted
  kms_key_id            = var.kms_key_id

  # Database 設定
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # Network 設定
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  port                   = local.port

  # 高可用性
  multi_az           = var.multi_az
  availability_zone  = var.availability_zone != null ? var.availability_zone : null
  ca_cert_identifier = var.ca_cert_identifier != null ? var.ca_cert_identifier : null

  # Backup 設定
  backup_retention_period = var.backup_retention_period
  backup_target           = var.backup_target
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"
  apply_immediately       = var.apply_immediately

  # 安全性
  deletion_protection         = var.deletion_protection
  skip_final_snapshot         = var.skip_final_snapshot
  final_snapshot_identifier   = var.final_snapshot_identifier != null ? var.final_snapshot_identifier : "${var.name}-final-snapshot"
  auto_minor_version_upgrade  = var.auto_minor_version_upgrade
  allow_major_version_upgrade = var.allow_major_version_upgrade

  # Parameter Group
  parameter_group_name = aws_db_parameter_group.this.name

  # 監控
  monitoring_interval             = var.monitoring_interval
  monitoring_role_arn             = var.monitoring_role_arn
  performance_insights_enabled    = var.performance_insights_enabled
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  replica_mode        = var.replica_mode != null ? var.replica_mode : null
  replicate_source_db = var.replicate_source_db != null ? var.replicate_source_db : null

  lifecycle {
    ignore_changes = [
      db_name,
      username,
      password,
    ]

    create_before_destroy = true
  }

  # 藍綠更新
  blue_green_update {
    enabled = var.blue_green_update
  }

  tags = var.tags
}

resource "aws_security_group_rule" "whitelists" {
  count = length(var.accessible_sg_ids)

  from_port                = local.port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = element(var.accessible_sg_ids, count.index)
  to_port                  = local.port
  type                     = "ingress"
}
