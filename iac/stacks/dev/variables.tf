###############################################################################
# Dev Stack — variables.tf
###############################################################################

variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "region" {
  type    = string
  default = "us-east-1"
}

###############################################################################
# VPC
###############################################################################
variable "vpc_cidr" {
  type = string
}

variable "availability_zones" {
  type = list(string)
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "private_subnet_cidrs" {
  type = list(string)
}

variable "single_nat_gateway" {
  type    = bool
  default = true
}

variable "vpc_security_groups" {
  type = map(object({
    description = string
    ingress_rules = list(object({
      description     = string
      from_port       = number
      to_port         = number
      protocol        = string
      cidr_blocks     = optional(list(string), [])
      security_groups = optional(list(string), [])
      self            = optional(bool, false)
    }))
    egress_rules = list(object({
      description     = string
      from_port       = number
      to_port         = number
      protocol        = string
      cidr_blocks     = optional(list(string), [])
      security_groups = optional(list(string), [])
    }))
  }))
  default = {}
}

###############################################################################
# ECR
###############################################################################
variable "ecr_repositories" {
  type = map(object({
    image_tag_mutability  = optional(string, "MUTABLE")
    scan_on_push          = optional(bool, true)
    encryption_type       = optional(string, null)
    kms_key_arn           = optional(string, null)
    force_delete          = optional(bool, false)
    lifecycle_policy      = optional(string, null)
    repository_policy     = optional(string, null)
  }))
  default = {}
}

###############################################################################
# EKS
###############################################################################
variable "eks_cluster_version" {
  type    = string
  default = "1.36"
}

variable "eks_endpoint_private_access" {
  type    = bool
  default = true
}

variable "eks_endpoint_public_access" {
  type    = bool
  default = true
}

variable "eks_public_access_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "eks_cluster_log_types" {
  type    = list(string)
  default = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "eks_node_groups" {
  type = map(object({
    instance_types             = list(string)
    capacity_type              = string
    ami_type                   = optional(string, "AL2023_x86_64_STANDARD")
    disk_size                  = number
    min_size                   = number
    max_size                   = number
    desired_size               = number
    max_unavailable_percentage = optional(number, 33)
    labels                     = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = optional(string)
      effect = string
    })), [])
  }))
  default = {}
}

variable "eks_addon_versions" {
  type    = map(string)
  default = {}
}

variable "eks_additional_addons" {
  type = map(object({
    addon_version = optional(string)
  }))
  default = {}
}

variable "eks_pod_identity_associations" {
  type = map(object({
    namespace           = string
    service_account     = string
    managed_policy_arns = optional(list(string), [])
    inline_policy       = optional(string)
  }))
  default = {}
}

###############################################################################
# RDS
###############################################################################
variable "rds_identifier" {
  type    = string
  default = "postgres"
}

variable "rds_engine" {
  type    = string
  default = "postgres"
}

variable "rds_engine_version" {
  type    = string
  default = "17.10"
}

variable "rds_instance_class" {
  type    = string
  default = "db.t3.medium"
}

variable "rds_parameter_group_family" {
  type    = string
  default = "postgres17"
}

variable "rds_db_parameters" {
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "immediate")
  }))
  default = []
}

variable "rds_allocated_storage" {
  type    = number
  default = 20
}

variable "rds_max_allocated_storage" {
  type    = number
  default = 100
}

variable "rds_db_name" {
  type = string
}

variable "rds_db_username" {
  type = string
}

variable "rds_db_password" {
  type      = string
  sensitive = true
  # Optional while the RDS module is disabled in main.tf.
  # Set via TF_VAR_rds_db_password when RDS is re-enabled (never hardcode).
  default = ""
}

variable "rds_multi_az" {
  type    = bool
  default = false
}

variable "rds_backup_retention_period" {
  type    = number
  default = 7
}

variable "rds_skip_final_snapshot" {
  type    = bool
  default = true
}

variable "rds_deletion_protection" {
  type    = bool
  default = false
}

variable "rds_monitoring_interval" {
  type    = number
  default = 0
}
