# RDS Postgres — the durable audit ledger (C01) plus identity/registry persistence. Private
# only: reachable from the node group security group, never from the internet.
resource "aws_db_subnet_group" "this" {
  name       = "${var.name_prefix}-db"
  subnet_ids = module.vpc.private_subnets
  tags       = local.tags
}

resource "aws_security_group" "db" {
  name        = "${var.name_prefix}-db"
  description = "Postgres access from the EKS node group only"
  vpc_id      = module.vpc.vpc_id
  tags        = local.tags
}

resource "aws_security_group_rule" "db_from_nodes" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.db.id
  source_security_group_id = module.eks.node_security_group_id
  description              = "Postgres from EKS worker nodes"
}

resource "random_password" "db" {
  length  = 32
  special = false # keep the password URL-safe for the SQLAlchemy DSN
}

resource "aws_db_instance" "this" {
  identifier     = "${var.name_prefix}-audit"
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_allocated_storage * 2
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  multi_az               = var.db_multi_az
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false

  # Trial-friendly lifecycle. For production, raise backup_retention_period and set
  # deletion_protection = true / skip_final_snapshot = false.
  backup_retention_period = 7
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true

  tags = local.tags
}

locals {
  # SQLAlchemy DSN the audit store + identity replay store consume, pointed at RDS.
  audit_database_url = "postgresql+psycopg://${var.db_username}:${random_password.db.result}@${aws_db_instance.this.address}:5432/${var.db_name}"
}
