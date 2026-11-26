terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # The bucket name comes from -backend-config in CI. No credentials here:
  # each job gets its own from configure-aws-credentials.
  backend "s3" {
    key          = "state/production/site.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Repo      = "MuhammadAbraiz/terraform-aws-pipeline"
    }
  }
}

data "aws_caller_identity" "current" {}
