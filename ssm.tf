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
