variable "aws_region" {
  description = "Regiao AWS. O Learner Lab so libera us-east-1."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Nome do ambiente, usado em tags e no nome dos recursos."
  type        = string
  default     = "production"
}

variable "db_username" {
  description = "Usuario administrador do PostgreSQL."
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Senha do usuario administrador. Gerar com: openssl rand -base64 32"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 16
    error_message = "A senha precisa de ao menos 16 caracteres."
  }
}

variable "allowed_cidr_blocks" {
  description = "Origens autorizadas na porta 5432. Sem valor, usa o CIDR da VPC default."
  type        = list(string)
  default     = null

  validation {
    condition     = var.allowed_cidr_blocks == null || !contains(coalesce(var.allowed_cidr_blocks, []), "0.0.0.0/0")
    error_message = "Banco nao vai aberto para a internet. Restrinja a origem."
  }
}
