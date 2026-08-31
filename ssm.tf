# A senha nao sai em output: quem precisa dela le este parametro, com a
# permissao de IAM correspondente. O output publica apenas o *nome* do
# parametro, que nao e segredo.
resource "aws_ssm_parameter" "db_password" {
  name        = "/car-repair-shop/db/password"
  description = "Senha do usuario administrador do RDS do car-repair-shop"
  type        = "SecureString"
  value       = var.db_password

  # SecureString padrao usa a chave gerenciada da conta (alias/aws/ssm).
  # Nao criamos chave KMS propria: o Learner Lab restringe IAM, e a chave
  # gerenciada ja cobre o requisito de cifra em repouso.
}

# Senha do administrador que a aplicacao cria na primeira subida.
#
# Gerada aqui, e nao informada por variavel, porque nao ha motivo para um
# humano escolher este valor: ninguem precisa decora-lo, e quem tiver a
# permissao le o parametro. Uma senha escolhida por pessoa acaba sendo fraca,
# reaproveitada, ou colada num arquivo de exemplo -- que foi exatamente o que
# aconteceu na Fase 2, com "admin123" versionado num repositorio publico.
resource "random_password" "admin_password" {
  length  = 24
  special = true

  # O caractere de barra quebra o parse do DATABASE_URL quando a senha entra
  # numa URI, e ":" e "@" tem significado em URI. Fora deles sobra entropia de
  # sobra em 24 caracteres.
  override_special = "!#%*-_=+?"
}

resource "aws_ssm_parameter" "admin_password" {
  name        = "/car-repair-shop/app/admin-password"
  description = "Senha do usuario admin semeado pela aplicacao na primeira subida"
  type        = "SecureString"
  value       = random_password.admin_password.result
}
