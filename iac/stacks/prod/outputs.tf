###############################################################################
# Prod Stack — outputs.tf
###############################################################################

output "vpc_id" { value = module.vpc.vpc_id }
output "public_subnet_ids" { value = module.vpc.public_subnet_ids }
output "private_subnet_ids" { value = module.vpc.private_subnet_ids }

output "eks_cluster_name" { value = module.eks.cluster_name }
output "eks_cluster_endpoint" { value = module.eks.cluster_endpoint }
output "eks_cluster_ca_certificate" {
  value     = module.eks.cluster_ca_certificate
  sensitive = true
}
output "eks_pod_identity_role_arns" { value = module.eks.pod_identity_role_arns }

output "ecr_repository_urls" { value = module.ecr.repository_urls }

output "rds_endpoint" { value = module.rds.db_endpoint }
output "rds_host" { value = module.rds.db_host }
output "rds_port" { value = module.rds.db_port }
