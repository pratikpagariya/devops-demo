terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    # Populated by apply.sh via -backend-config flags
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "devops-demo"
      Environment = "dev"
      ManagedBy   = "terraform"
      Owner       = "devops-team"
    }
  }
}
