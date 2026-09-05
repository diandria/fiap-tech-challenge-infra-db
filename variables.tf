variable "aws_region" {
  description = "Regiao AWS. O Learner Lab so libera us-east-1."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name, used in tags and in resource names."
  type        = string
  default     = "production"
}

variable "db_username" {
  description = "Usuario administrador do PostgreSQL."
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Administrator password. Generate with: openssl rand -base64 32"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 16
    error_message = "The password needs at least 16 characters."
  }
}

variable "allowed_cidr_blocks" {
  description = "Sources allowed on port 5432. Empty means the default VPC CIDR."
  type        = list(string)
  default     = null

  validation {
    condition     = var.allowed_cidr_blocks == null || !contains(coalesce(var.allowed_cidr_blocks, []), "0.0.0.0/0")
    error_message = "The database is not exposed to the internet. Restrict the source."
  }
}
