resource "aws_db_parameter_group" "main" {
  name   = local.db_identifier
  family = "postgres16"

  description = "Parametros do PostgreSQL do car-repair-shop"

  # Query acima de 1s vai para o log. Coerente com o pilar de observabilidade
  # da fase: consulta lenta some no agregado de latencia HTTP, mas aparece aqui.
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

  # Sem endereco publico: o acesso vem de dentro da VPC, pelo security group.
  publicly_accessible = false

  # As tres linhas abaixo sao escolhas deliberadas de ambiente efemero, onde o
  # destroy precisa ser limpo e rapido para nao queimar o orcamento do lab.
  # Em ambiente real as tres seriam o oposto: snapshot final obrigatorio,
  # protecao contra delecao ligada e retencao de backup de varios dias.
  skip_final_snapshot     = true
  deletion_protection     = false
  backup_retention_period = 0

  # Mudanca de parametro nao espera a janela de manutencao. Aceitavel porque
  # nao ha trafego de producao real; em producao seria o contrario.
  apply_immediately = true
}
