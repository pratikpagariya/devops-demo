###############################################################################
# Dev Stack — main.tf
# Wires VPC, EKS, ECR, and RDS modules together
###############################################################################

locals {
  project     = var.project
  environment = var.environment
  region      = var.region

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Owner       = "devops-team"
  }
}

###############################################################################
# VPC
###############################################################################
module "vpc" {
  source = "../../modules/vpc"

  project              = local.project
  environment          = local.environment
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  single_nat_gateway   = var.single_nat_gateway
  security_groups      = var.vpc_security_groups
  tags                 = local.common_tags
}

###############################################################################
# ECR
###############################################################################
module "ecr" {
  source = "../../modules/ecr"

  project      = local.project
  environment  = local.environment
  repositories = var.ecr_repositories
  tags         = local.common_tags
}

###############################################################################
# EKS
###############################################################################
module "eks" {
  source = "../../modules/eks"

  project    = local.project
  environment = local.environment

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  cluster_version         = var.eks_cluster_version
  endpoint_private_access = var.eks_endpoint_private_access
  endpoint_public_access  = var.eks_endpoint_public_access
  public_access_cidrs     = var.eks_public_access_cidrs
  cluster_log_types       = var.eks_cluster_log_types

  node_groups = var.eks_node_groups

  addon_versions    = var.eks_addon_versions
  additional_addons = var.eks_additional_addons

  pod_identity_associations = var.eks_pod_identity_associations

  tags = local.common_tags
}

###############################################################################
# RDS  (DISABLED — temporarily commented out to skip during deploy.
#        Re-enable by removing the /* */ wrapper below.)
###############################################################################
/*
module "rds" {
  source = "../../modules/rds"

  project     = local.project
  environment = local.environment
  identifier  = var.rds_identifier

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  engine                 = var.rds_engine
  engine_version         = var.rds_engine_version
  instance_class         = var.rds_instance_class
  parameter_group_family = var.rds_parameter_group_family
  db_parameters          = var.rds_db_parameters

  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_max_allocated_storage
  storage_encrypted     = true

  db_name     = var.rds_db_name
  db_username = var.rds_db_username
  db_password = var.rds_db_password

  # Allow EKS nodes to connect to RDS
  allowed_security_group_ids = [module.eks.node_security_group_id]

  multi_az                = var.rds_multi_az
  backup_retention_period = var.rds_backup_retention_period
  skip_final_snapshot     = var.rds_skip_final_snapshot
  deletion_protection     = var.rds_deletion_protection
  monitoring_interval     = var.rds_monitoring_interval

  tags = local.common_tags
}
*/
