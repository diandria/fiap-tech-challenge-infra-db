# Consumed by infra-k8s, the lambda repository and the application, through
# terraform_remote_state pointing at this repository's backend.

output "db_endpoint" {
  description = "RDS DNS address. Resolves to a private VPC address."
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
  description = "RDS security group. infra-k8s references it to allow the nodes."
  value       = aws_security_group.rds.id
}

output "db_password_parameter" {
  description = "Name of the SSM parameter holding the password. Not the password."
  value       = aws_ssm_parameter.db_password.name
}

output "admin_password_parameter" {
  description = "Name of the SSM parameter holding the application admin password."
  value       = aws_ssm_parameter.admin_password.name
}
