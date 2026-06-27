###############################################################################
# Backend Bootstrap — creates the S3 bucket for Terraform state.
# Locking uses S3 native state locking (use_lockfile=true) — no DynamoDB table
# is required (needs Terraform >= 1.11).
# Run ONCE before any stack: terraform -chdir=iac/backend apply
###############################################################################

variable "project" {
  description = "Project name"
  type        = string
  default     = "devops-demo"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "environments" {
  description = "Environments to create state buckets for"
  type        = list(string)
  default     = ["dev", "prod"]
}

locals {
  bucket_name = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"

  common_tags = {
    Project   = var.project
    ManagedBy = "terraform"
    Owner     = "devops-team"
    Purpose   = "terraform-state"
  }
}

data "aws_caller_identity" "current" {}

###############################################################################
# S3 State Bucket
###############################################################################
resource "aws_s3_bucket" "tfstate" {
  bucket        = local.bucket_name
  force_destroy = false

  tags = merge(local.common_tags, {
    Name = local.bucket_name
  })
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

###############################################################################
# State folder prefixes per environment (S3 "directories")
###############################################################################
resource "aws_s3_object" "state_prefix" {
  for_each = toset(var.environments)

  bucket  = aws_s3_bucket.tfstate.id
  key     = "${each.value}/.keep"
  content = ""

  tags = local.common_tags
}

###############################################################################
# Outputs for use by apply.sh
###############################################################################
output "state_bucket" {
  value = aws_s3_bucket.tfstate.id
}

output "state_bucket_arn" {
  value = aws_s3_bucket.tfstate.arn
}

###############################################################################
# Provider / versions
###############################################################################
terraform {
  required_version = ">= 1.11.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Owner     = "devops-team"
    }
  }
}
