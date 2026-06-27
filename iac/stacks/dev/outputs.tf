###############################################################################
# Dev Stack — outputs.tf
###############################################################################

# VPC
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

# EKS
output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_ca_certificate" {
  description = "EKS cluster CA certificate (base64)"
  value       = module.eks.cluster_ca_certificate
  sensitive   = true
}

output "eks_pod_identity_role_arns" {
  description = "IAM role ARNs for Pod Identity associations"
  value       = module.eks.pod_identity_role_arns
}

# ECR
output "ecr_repository_urls" {
  description = "ECR repository URLs"
  value       = module.ecr.repository_urls
}

# RDS  (DISABLED — these reference module.rds, which is commented out in main.tf.
#        Re-enable together with the module by removing the /* */ wrapper.)
/*
output "rds_endpoint" {
  description = "RDS connection endpoint"
  value       = module.rds.db_endpoint
}

output "rds_host" {
  value = module.rds.db_host
}

output "rds_port" {
  value = module.rds.db_port
}
*/
