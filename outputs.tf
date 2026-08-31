# Consumidos por infra-k8s (M5), pela lambda (M6) e pela aplicacao (M8),
# via terraform_remote_state apontando para o backend deste repositorio.

output "db_endpoint" {
  description = "Endereco DNS do RDS. Resolve para IP privado da VPC."
  value       = aws_db_instance.main.address
}

output "db_port" {
  description = "Porta do PostgreSQL."
  value       = aws_db_instance.main.port
}

output "db_name" {
  description = "Nome do banco criado na instancia."
  value       = aws_db_instance.main.db_name
}

output "db_username" {
  description = "Usuario administrador."
  value       = aws_db_instance.main.username
  sensitive   = true
}

output "db_security_group_id" {
  description = "Security group do RDS. O infra-k8s referencia para liberar os nos."
  value       = aws_security_group.rds.id
}

output "db_password_parameter" {
  description = "Nome do parametro SSM que guarda a senha. Nao e a senha."
  value       = aws_ssm_parameter.db_password.name
}

output "admin_password_parameter" {
  description = "Nome do parametro SSM com a senha do admin da aplicacao."
  value       = aws_ssm_parameter.admin_password.name
}
