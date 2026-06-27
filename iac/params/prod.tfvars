###############################################################################
# Prod Environment Parameters
###############################################################################

project     = "devops-demo"
environment = "prod"
region      = "us-east-1"

###############################################################################
# Networking
###############################################################################
vpc_cidr             = "10.20.0.0/16"
availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
public_subnet_cidrs  = ["10.20.1.0/24", "10.20.2.0/24", "10.20.3.0/24"]
private_subnet_cidrs = ["10.20.11.0/24", "10.20.12.0/24", "10.20.13.0/24"]

# Prod uses one NAT per AZ for HA
single_nat_gateway = false

###############################################################################
# ECR Repositories
###############################################################################
ecr_repositories = {
  api = {
    image_tag_mutability = "IMMUTABLE"
    scan_on_push         = true
    force_delete         = false
  }
  worker = {
    image_tag_mutability = "IMMUTABLE"
    scan_on_push         = true
    force_delete         = false
  }
  frontend = {
    image_tag_mutability = "IMMUTABLE"
    scan_on_push         = true
    force_delete         = false
  }
}

###############################################################################
# EKS
###############################################################################
eks_cluster_version         = "1.36"
eks_endpoint_private_access = true
eks_endpoint_public_access  = false  # private-only in prod
eks_public_access_cidrs     = []

eks_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

eks_node_groups = {
  general = {
    instance_types = ["m7i.xlarge"]
    capacity_type  = "ON_DEMAND"
    ami_type       = "AL2023_x86_64_STANDARD"
    disk_size      = 100
    min_size       = 2
    max_size       = 10
    desired_size   = 3
    labels = {
      role = "general"
    }
  }
  spot = {
    instance_types = ["m7i.large", "m6i.large", "m6a.large"]
    capacity_type  = "SPOT"
    ami_type       = "AL2023_x86_64_STANDARD"
    disk_size      = 100
    min_size       = 0
    max_size       = 20
    desired_size   = 2
    labels = {
      role        = "spot"
      "spot-node" = "true"
    }
    taints = [
      {
        key    = "spot"
        value  = "true"
        effect = "NO_SCHEDULE"
      }
    ]
  }
}

eks_pod_identity_associations = {
  api-s3 = {
    namespace       = "app"
    service_account = "api-service-account"
    managed_policy_arns = [
      "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
    ]
  }
  worker-s3 = {
    namespace       = "app"
    service_account = "worker-service-account"
    managed_policy_arns = [
      "arn:aws:iam::aws:policy/AmazonS3FullAccess"
    ]
  }
}

###############################################################################
# RDS
###############################################################################
rds_identifier             = "postgres"
rds_engine                 = "postgres"
rds_engine_version         = "17.10"
rds_instance_class         = "db.r6g.large"
rds_parameter_group_family = "postgres17"

rds_db_parameters = [
  {
    name  = "log_connections"
    value = "1"
  },
  {
    name  = "log_disconnections"
    value = "1"
  },
  {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"
  }
]

rds_allocated_storage     = 100
rds_max_allocated_storage = 500

rds_db_name     = "appdb"
rds_db_username = "dbadmin"
# rds_db_password is supplied via TF_VAR_rds_db_password env var

rds_multi_az                = true
rds_backup_retention_period = 30
rds_skip_final_snapshot     = false
rds_deletion_protection     = true
rds_monitoring_interval     = 60
