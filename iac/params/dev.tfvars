###############################################################################
# Dev Environment Parameters
###############################################################################

project     = "devops-demo"
environment = "dev"
region      = "us-east-1"

###############################################################################
# Networking
###############################################################################
vpc_cidr             = "10.10.0.0/16"
availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
public_subnet_cidrs  = ["10.10.1.0/24", "10.10.2.0/24", "10.10.3.0/24"]
private_subnet_cidrs = ["10.10.11.0/24", "10.10.12.0/24", "10.10.13.0/24"]

# Dev uses single NAT to save cost
single_nat_gateway = true

###############################################################################
# ECR Repositories
###############################################################################
ecr_repositories = {
  api = {
    image_tag_mutability = "MUTABLE"
    scan_on_push         = true
    force_delete         = true
  }
  worker = {
    image_tag_mutability = "MUTABLE"
    scan_on_push         = true
    force_delete         = true
  }
  frontend = {
    image_tag_mutability = "MUTABLE"
    scan_on_push         = true
    force_delete         = true
  }
  # Todo-List-App images — CI (Jenkins/Buildah) pushes here; ArgoCD deploys them.
  todo-backend = {
    image_tag_mutability = "MUTABLE"
    scan_on_push         = true
    force_delete         = true
  }
  todo-frontend = {
    image_tag_mutability = "MUTABLE"
    scan_on_push         = true
    force_delete         = true
  }
}

###############################################################################
# EKS
###############################################################################
eks_cluster_version         = "1.36"
eks_endpoint_private_access = true
eks_endpoint_public_access  = true
eks_public_access_cidrs     = ["0.0.0.0/0"]

eks_cluster_log_types = ["api", "audit", "authenticator"]

eks_node_groups = {
  general = {
    instance_types = ["c7i-flex.large"]
    capacity_type  = "ON_DEMAND"
    ami_type       = "AL2023_x86_64_STANDARD"
    disk_size      = 20
    min_size       = 2
    max_size       = 5
    desired_size   = 2
    labels = {
      role = "general"
    }
  }
}

# Pod Identity: API pods get S3 read access + ECR pull
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
  # Jenkins (controller + agents running under the 'jenkins' SA) push images to ECR.
  jenkins-ecr = {
    namespace       = "jenkins"
    service_account = "jenkins"
    managed_policy_arns = [
      "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
    ]
  }
}

# Extra cluster addons beyond the defaults (coredns, kube-proxy, vpc-cni,
# eks-pod-identity-agent). EBS CSI is needed for PVCs (Jenkins, SonarQube,
# Prometheus, Grafana, Loki). Its Pod Identity association is in platform.tf.
eks_additional_addons = {
  aws-ebs-csi-driver = {}
}

###############################################################################
# RDS
###############################################################################
rds_identifier             = "postgres"
rds_engine                 = "postgres"
rds_engine_version         = "17.10"
rds_instance_class         = "db.t3.medium"
rds_parameter_group_family = "postgres17"

rds_allocated_storage     = 20
rds_max_allocated_storage = 100

rds_db_name     = "appdb"
rds_db_username = "dbadmin"
# rds_db_password is supplied via TF_VAR_rds_db_password env var

rds_multi_az                = false
rds_backup_retention_period = 3
rds_skip_final_snapshot     = true
rds_deletion_protection     = false
rds_monitoring_interval     = 0

###############################################################################
# Platform Secrets (AWS Secrets Manager)
# Consumed in-cluster by External Secrets Operator → Kubernetes Secrets.
# Generated passwords are stored in Secrets Manager; rotate them there
# (Terraform ignores secret value drift after creation).
###############################################################################
platform_secrets = {
  jenkins-admin = {
    description = "Jenkins admin credentials"
    generate    = true
    username    = "admin"
  }
  grafana-admin = {
    description = "Grafana admin credentials"
    generate    = true
    username    = "admin"
  }
  sonarqube-db = {
    description = "SonarQube bundled PostgreSQL credentials"
    generate    = true
    username    = "sonarUser"
  }
  sonarqube-monitoring = {
    description = "SonarQube web monitoring passcode"
    generate    = true
    special     = false
  }
  # Placeholders — update the real values directly in Secrets Manager.
  git-credentials = {
    description   = "Git credentials (PAT) for Jenkins/ArgoCD — UPDATE in Secrets Manager"
    secret_string = "{\"username\":\"git-user\",\"password\":\"REPLACE_ME_PAT\"}"
  }
  registry-credentials = {
    description   = "Container registry credentials — UPDATE in Secrets Manager"
    secret_string = "{\"username\":\"registry-user\",\"password\":\"REPLACE_ME_TOKEN\"}"
  }
  sonarqube-token = {
    description   = "SonarQube analysis token for Jenkins — UPDATE with a real token after SonarQube is up"
    secret_string = "{\"token\":\"REPLACE_ME_SONAR_TOKEN\"}"
  }
}
