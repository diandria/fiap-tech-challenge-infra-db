terraform {
  backend "s3" {
    bucket = "fiap-tech-challenge-tfstate-108337503570"
    key    = "infra-db/terraform.tfstate"
    region = "us-east-1"

    # Encryption at rest. The state holds the database password in clear text;
    # this line and .gitignore are what keep it from leaking.
    encrypt = true

    # Native S3 locking, via a .tflock file next to the state. Replaces
    # dynamodb_table, deprecated since Terraform 1.11: one less table to
    # create, pay for and remember to destroy.
    use_lockfile = true
  }
}
