terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Bucket/region/key/lockfile are supplied at init time via -backend-config,
  # since the actual bucket name depends on the AWS account id.
  backend "s3" {}
}
