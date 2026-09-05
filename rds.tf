resource "aws_db_parameter_group" "main" {
  name   = local.db_identifier
  family = "postgres16"

  description = "Parametros do PostgreSQL do car-repair-shop"

  # Queries over 1s go to the log. A slow query disappears into the aggregate
  # HTTP latency but shows up here.
  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "main" {
  identifier = local.db_identifier

  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t3.micro"

  allocated_storage = 20
  storage_encrypted = true

  db_name  = "car_repair_shop"
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.main.name

  # No public address: access comes from inside the VPC, via the security group.
  publicly_accessible = false

  # The three settings below suit an ephemeral environment, where destroy has
  # to be clean and fast. A real environment would invert all three: mandatory
  # final snapshot, deletion protection on, and multi-day backup retention.
  skip_final_snapshot     = true
  deletion_protection     = false
  backup_retention_period = 0

  # Parameter changes skip the maintenance window. Acceptable without real
  # production traffic; in production it would be the opposite.
  apply_immediately = true
}
