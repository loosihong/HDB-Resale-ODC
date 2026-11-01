# RDS for PostgreSQL in the data zone. Multi-AZ: primary in one AZ, synchronous
# standby in the other, automatic failover. The ODC runtime manages the app
# tables in the stage database.

resource "aws_db_subnet_group" "this" {
  name       = "${local.name}-db"
  subnet_ids = module.data_vpc.subnet_ids["db"]
}

resource "aws_security_group" "db" {
  name        = "${local.name}-db"
  description = "PostgreSQL from intranet EKS only"
  vpc_id      = module.data_vpc.vpc_id
  tags        = { Name = "${local.name}-db" }
}

# Cross-VPC (via Transit Gateway), so the rule uses the intranet app subnet CIDRs.
resource "aws_vpc_security_group_ingress_rule" "db_from_intranet_apps" {
  for_each          = toset(module.intranet_vpc.subnet_cidrs["app"])
  security_group_id = aws_security_group.db.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
  description       = "PostgreSQL from intranet app subnet"
}

resource "aws_db_parameter_group" "this" {
  name   = "${local.name}-pg${var.db_engine_version}"
  family = "postgres${var.db_engine_version}"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }
}

resource "aws_db_instance" "this" {
  identifier     = "${local.name}-pg"
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage_gb
  max_allocated_storage = var.db_max_allocated_storage_gb
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.main.arn

  db_name  = "postgres"
  username = "dbadmin"
  # Master password generated and rotated by RDS in Secrets Manager.
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.main.arn

  multi_az               = var.db_multi_az
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false

  iam_database_authentication_enabled = true

  backup_retention_period   = var.db_backup_retention_days
  backup_window             = "18:00-19:00" # 02:00-03:00 SGT
  maintenance_window        = "sun:19:00-sun:20:00"
  copy_tags_to_snapshot     = true
  deletion_protection       = var.db_deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.name}-pg-final"

  auto_minor_version_upgrade      = true
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.main.arn
  performance_insights_retention_period = 7
}
