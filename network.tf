# A VPC nao e criada aqui: este repositorio consome a default do Learner Lab.
# A fronteira esta registrada no README.
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

locals {
  # Sem valor explicito, a origem permitida e a propria VPC. Deixar o default
  # amarrado ao CIDR descoberto evita que alguem herde um bloco largo por engano.
  ingress_cidr_blocks = coalesce(var.allowed_cidr_blocks, [data.aws_vpc.default.cidr_block])
}

# O RDS exige subnet group com pelo menos duas AZs, mesmo sem Multi-AZ.
# Verificado na conta: a VPC default tem 6 AZs.
resource "aws_db_subnet_group" "main" {
  name       = local.db_identifier
  subnet_ids = data.aws_subnets.default.ids

  description = "Subnets da VPC default usadas pelo RDS do car-repair-shop"
}

resource "aws_security_group" "rds" {
  name        = local.db_identifier
  description = "Acesso ao PostgreSQL do car-repair-shop, restrito a origem interna"
  vpc_id      = data.aws_vpc.default.id

  # O ideal seria referenciar o security group dos nos do EKS, mas isso criaria
  # dependencia circular entre infra-db e infra-k8s. Quebrada com uma variavel,
  # cujo default e o CIDR da VPC: dentro da rede, nunca aberto para a internet.
  ingress {
    description = "PostgreSQL a partir da rede interna"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Egress irrestrito e inofensivo aqui: o RDS nao inicia conexoes de saida.
  # Restringir nao aumenta a seguranca e quebra a resolucao de DNS interna.
  #trivy:ignore:AVD-AWS-0104
  egress {
    description = "Saida irrestrita; o RDS nao inicia conexoes"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
