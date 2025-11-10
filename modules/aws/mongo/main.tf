# MongoDB (DocumentDB) Cluster
resource "aws_docdb_cluster" "this" {
  cluster_identifier           = var.cluster_identifier
  engine                       = "docdb"
  master_username              = var.master_username
  master_password              = var.master_password
  db_subnet_group_name         = aws_docdb_subnet_group.this.name
  vpc_security_group_ids       = [aws_security_group.mongodb.id]
  skip_final_snapshot          = var.skip_final_snapshot
  final_snapshot_identifier    = var.skip_final_snapshot ? null : (var.final_snapshot_identifier != null ? var.final_snapshot_identifier : "${var.cluster_identifier}-final-snapshot")
  deletion_protection          = var.deletion_protection
  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window

  tags = merge(var.tags, {
    name = var.cluster_identifier
  })

  lifecycle {
    prevent_destroy = false
    ignore_changes = [
      master_password
    ]
  }
}

# MongoDB (DocumentDB) Cluster Instance
resource "aws_docdb_cluster_instance" "this" {
  count              = var.instance_count
  identifier         = "${var.cluster_identifier}-${count.index + 1}"
  cluster_identifier = aws_docdb_cluster.this.id
  instance_class     = var.instance_class

  tags = merge(var.tags, {
    name = "${var.cluster_identifier}-${count.index + 1}"
  })
}

# Subnet Group for DocumentDB
resource "aws_docdb_subnet_group" "this" {
  name       = "${var.cluster_identifier}-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, {
    name = "${var.cluster_identifier}-subnet-group"
  })
}

# Security Group for MongoDB
resource "aws_security_group" "mongodb" {
  name        = "${var.cluster_identifier}-sg"
  description = "Security group for MongoDB cluster"
  vpc_id      = var.vpc_id

  # Inbound rule for MongoDB/DocumentDB port (27017)
  ingress {
    description     = "MongoDB/DocumentDB from VPC"
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = var.allowed_security_groups
    cidr_blocks     = var.allowed_cidr_blocks
  }

  # Outbound rule
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    name = "${var.cluster_identifier}-sg"
  })
}

# Parameter Group for DocumentDB
resource "aws_docdb_cluster_parameter_group" "this" {
  family      = "docdb4.0"
  name        = "${var.cluster_identifier}-parameter-group"
  description = "Parameter group for ${var.cluster_identifier}"

  dynamic "parameter" {
    for_each = var.cluster_parameters
    content {
      name  = parameter.value.name
      value = parameter.value.value
    }
  }

  tags = merge(var.tags, {
    name = "${var.cluster_identifier}-parameter-group"
  })
}

# CloudWatch Log Group for MongoDB
resource "aws_cloudwatch_log_group" "mongodb" {
  name              = "/aws/docdb/${var.cluster_identifier}"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    name = "${var.cluster_identifier}-log-group"
  })
}
