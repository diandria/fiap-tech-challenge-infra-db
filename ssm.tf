# The password is not exposed as an output: whoever needs it reads this
# parameter with the matching IAM permission. The output publishes only the
# parameter *name*, which is not a secret.
resource "aws_ssm_parameter" "db_password" {
  name        = "/car-repair-shop/db/password"
  description = "Administrator password for the car-repair-shop RDS"
  type        = "SecureString"
  value       = var.db_password

  # SecureString defaults to the account-managed key (alias/aws/ssm). No
  # dedicated KMS key: the Learner Lab restricts IAM, and the managed key
  # already covers encryption at rest.
}

# Password for the administrator the application seeds on first start.
#
# Generated here rather than passed in as a variable: nobody needs to memorise
# it, and whoever has the permission reads the parameter. A human-chosen
# password tends to end up weak, reused, or pasted into an example file, which
# is what happened in Phase 2 with "admin123" committed to a public repo.
resource "random_password" "admin_password" {
  length  = 24
  special = true

  # A slash breaks DATABASE_URL parsing when the password goes into a URI, and
  # ":" and "@" are URI-significant. 24 characters leave ample entropy without
  # them.
  override_special = "!#%*-_=+?"
}

resource "aws_ssm_parameter" "admin_password" {
  name        = "/car-repair-shop/app/admin-password"
  description = "Password for the admin user the application seeds on first start"
  type        = "SecureString"
  value       = random_password.admin_password.result
}
