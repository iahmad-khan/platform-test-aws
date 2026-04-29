resource "aws_kms_key" "rds" {
  description             = "KMS key for RDS Aurora encryption — ${var.name}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = merge(var.tags, { Name = "${var.name}-rds-kms" })
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${var.name}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

resource "aws_db_subnet_group" "this" {
  name        = "${var.name}-rds"
  description = "Aurora subnet group — private subnets only"
  subnet_ids  = var.private_subnet_ids
  tags        = merge(var.tags, { Name = "${var.name}-rds-subnet-group" })
}

resource "aws_rds_cluster_parameter_group" "this" {
  name        = "${var.name}-aurora-pg16"
  family      = "aurora-postgresql16"
  description = "Aurora PostgreSQL 16 cluster parameters"

  parameter {
    name  = "ssl"
    value = "1"
  }

  tags = var.tags
}

resource "aws_rds_cluster" "this" {
  cluster_identifier      = var.name
  engine                  = "aurora-postgresql"
  engine_version          = var.engine_version
  database_name           = var.database_name
  db_subnet_group_name    = aws_db_subnet_group.this.name
  vpc_security_group_ids  = [var.rds_sg_id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name

  serverlessv2_scaling_configuration {
    min_capacity = var.min_capacity
    max_capacity = var.max_capacity
  }

  # Credentials managed by Secrets Manager automatically
  manage_master_user_password = true
  master_username             = "postgres"

  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn

  backup_retention_period = var.backup_retention_period
  deletion_protection     = var.deletion_protection
  skip_final_snapshot     = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name}-final-snapshot"
  apply_immediately       = var.apply_immediately

  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = var.tags

  lifecycle {
    ignore_changes = [final_snapshot_identifier]
  }
}

resource "aws_rds_cluster_instance" "this" {
  count              = var.instance_count
  identifier         = "${var.name}-${count.index}"
  cluster_identifier = aws_rds_cluster.this.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.this.engine
  engine_version     = aws_rds_cluster.this.engine_version

  db_subnet_group_name = aws_db_subnet_group.this.name
  apply_immediately    = var.apply_immediately

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null
  performance_insights_kms_key_id       = var.performance_insights_enabled ? aws_kms_key.rds.arn : null

  tags = merge(var.tags, {
    Name = "${var.name}-${count.index == 0 ? "writer" : "reader-${count.index}"}"
  })
}
