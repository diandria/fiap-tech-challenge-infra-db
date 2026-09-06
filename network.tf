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
  # name_prefix and create_before_destroy: description is immutable and forces
  # replacement. The new group must exist before the instance moves to it, and
  # the old one can only go after that -- the Learner Lab denies detaching the
  # RDS ENI by force, which is what deleting an in-use group falls back to.
  name_prefix = "${local.db_identifier}-"
  description = "Access to the car-repair-shop PostgreSQL, restricted to internal sources"
  vpc_id      = data.aws_vpc.default.id

  lifecycle {
    create_before_destroy = true
  }

  # Referencing the EKS node security group would create a circular dependency
  # between infra-db and infra-k8s. A variable breaks it; its default is the VPC
  # CIDR, so access stays inside the network and never reaches the internet.
  ingress {
    description = "PostgreSQL from the internal network"
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
