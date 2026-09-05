# The VPC is not created here: this repository consumes the Learner Lab
# default. The boundary is documented in the README.
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
  # With no explicit value the allowed source is the VPC itself. Tying the
  # default to the discovered CIDR avoids inheriting a wider block by mistake.
  ingress_cidr_blocks = coalesce(var.allowed_cidr_blocks, [data.aws_vpc.default.cidr_block])
}

# RDS requires a subnet group spanning at least two AZs, even without
# Multi-AZ. The default VPC in this account has 6.
resource "aws_db_subnet_group" "main" {
  name       = local.db_identifier
  subnet_ids = data.aws_subnets.default.ids

  description = "Default VPC subnets used by the car-repair-shop RDS"
}

resource "aws_security_group" "rds" {
  name        = local.db_identifier
  description = "Acesso ao PostgreSQL do car-repair-shop, restrito a origem interna"
  vpc_id      = data.aws_vpc.default.id

  # Referencing the EKS node security group would create a circular dependency
  # between infra-db and infra-k8s. A variable breaks it; its default is the VPC
  # CIDR, so access stays inside the network and never reaches the internet.
  ingress {
    description = "PostgreSQL a partir da rede interna"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = local.ingress_cidr_blocks
  }

  # Unrestricted egress is harmless here: RDS does not open outbound
  # connections. Restricting it adds no security and breaks internal DNS.
  #trivy:ignore:AVD-AWS-0104
  egress {
    description = "Unrestricted egress; RDS does not open connections"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
