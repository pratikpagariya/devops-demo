###############################################################################
# EKS Module — variables.tf
###############################################################################

variable "project" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where EKS will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for EKS nodes and control plane"
  type        = list(string)
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.36"
}

variable "endpoint_private_access" {
  description = "Enable private API endpoint"
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Enable public API endpoint"
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to access the public endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_log_types" {
  description = "EKS cluster log types to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "cluster_encryption_key_arn" {
  description = "KMS key ARN for encrypting Kubernetes secrets (null = disabled)"
  type        = string
  default     = null
}

variable "node_groups" {
  description = "Map of managed node group configurations"
  type = map(object({
    instance_types             = list(string)
    capacity_type              = string # ON_DEMAND or SPOT
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

variable "addon_versions" {
  description = "Override addon versions (null = use latest compatible)"
  type        = map(string)
  default     = {}
}

variable "additional_addons" {
  description = "Additional EKS addons beyond the defaults"
  type = map(object({
    addon_version = optional(string)
  }))
  default = {}
}

variable "pod_identity_associations" {
  description = "Map of Pod Identity associations (EKS Pod Identity, not IRSA)"
  type = map(object({
    namespace           = string
    service_account     = string
    managed_policy_arns = optional(list(string), [])
    inline_policy       = optional(string)
  }))
  default = {}
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
