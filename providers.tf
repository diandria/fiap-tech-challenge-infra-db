provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "car-repair-shop"
      Phase       = "3"
      ManagedBy   = "terraform"
      Repository  = "fiap-tech-challenge-infra-db"
      Environment = var.environment
    }
  }
}
