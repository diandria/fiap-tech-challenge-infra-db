terraform {
  backend "s3" {
    bucket = "fiap-tech-challenge-tfstate-108337503570"
    key    = "infra-db/terraform.tfstate"
    region = "us-east-1"

    # Cifra em repouso. O estado guarda a senha do banco em texto claro:
    # esta linha e o .gitignore sao o que impede o vazamento.
    encrypt = true

    # Trava nativa do S3, via arquivo .tflock ao lado do estado. Substitui o
    # dynamodb_table, que o Terraform deprecou a partir da versao 1.11: uma
    # tabela a menos para criar, pagar e lembrar de destruir.
    use_lockfile = true
  }
}
