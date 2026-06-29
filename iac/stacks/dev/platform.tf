###############################################################################
# Dev Stack — platform.tf
# CI/CD + platform layer:
#   - AWS Secrets Manager secrets (consumed by External Secrets Operator)
#   - EKS Pod Identity roles for the platform controllers
#     (AWS LB Controller, Cluster Autoscaler, External Secrets, EBS CSI)
#
# Workload Pod Identity (api-s3, etc.) is driven through the eks module via
# var.eks_pod_identity_associations. Platform-controller identities live here
# so this whole layer stays decoupled from the eks module call in main.tf.
###############################################################################

data "aws_caller_identity" "platform" {}

locals {
  account_id = data.aws_caller_identity.platform.account_id

  # IAM scoping: every secret this stack creates matches this ARN pattern.
  secret_arn_pattern = "arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:${local.project}-${local.environment}-*"

  # Platform controllers → Kubernetes service accounts → IAM permissions.
  platform_controllers = {
    aws-load-balancer-controller = {
      namespace           = "kube-system"
      service_account     = "aws-load-balancer-controller"
      inline_policy       = file("${path.module}/policies/aws-load-balancer-controller.json")
      managed_policy_arns = []
    }
    cluster-autoscaler = {
      namespace           = "kube-system"
      service_account     = "cluster-autoscaler"
      inline_policy       = file("${path.module}/policies/cluster-autoscaler.json")
      managed_policy_arns = []
    }
    external-secrets = {
      namespace       = "external-secrets"
      service_account = "external-secrets"
      inline_policy = templatefile("${path.module}/policies/external-secrets.json", {
        secret_arn_pattern = local.secret_arn_pattern
      })
      managed_policy_arns = []
    }
    ebs-csi-controller = {
      namespace           = "kube-system"
      service_account     = "ebs-csi-controller-sa"
      inline_policy       = null
      managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"]
    }
  }

  # Flatten managed-policy attachments for for_each
  platform_managed_attachments = merge([
    for ck, c in local.platform_controllers : {
      for arn in c.managed_policy_arns :
      "${ck}__${basename(arn)}" => { controller = ck, policy_arn = arn }
    }
  ]...)
}

###############################################################################
# Secrets Manager
###############################################################################
module "secrets" {
  source = "../../modules/secrets"

  project     = local.project
  environment = local.environment

  # Dev: force immediate deletion (no 7-day recovery window) so repeated
  # destroy/apply cycles don't hit "secret already scheduled for deletion".
  # The git-credentials + sonarqube-token VALUES come from the gitignored
  # secrets.auto.tfvars (vars below); all other secrets keep their tfvars value.
  secrets = {
    for k, v in var.platform_secrets : k => merge(
      v,
      { recovery_window_in_days = 0 },
      k == "git-credentials" ? { secret_string = jsonencode({ username = var.github_username, password = var.github_token }) } : {},
      k == "sonarqube-token" ? { secret_string = jsonencode({ token = var.sonarqube_token }) } : {},
    )
  }

  tags = local.common_tags
}

###############################################################################
# Sensitive token values. Set these in a GITIGNORED secrets.auto.tfvars
# (Terraform auto-loads *.auto.tfvars). They default to placeholders so a fresh
# apply still works; update them with real values + re-apply.
###############################################################################
variable "github_username" {
  description = "GitHub username for the github-credentials Jenkins credential"
  type        = string
  default     = "git-user"
}
variable "github_token" {
  description = "GitHub PAT — set in secrets.auto.tfvars (gitignored); never commit"
  type        = string
  sensitive   = true
  default     = "REPLACE_ME_PAT"
}
variable "sonarqube_token" {
  description = "SonarQube token — set in secrets.auto.tfvars after SonarQube is up"
  type        = string
  sensitive   = true
  default     = "REPLACE_ME_SONAR_TOKEN"
}

###############################################################################
# Pod Identity IAM roles for platform controllers
###############################################################################
resource "aws_iam_role" "platform" {
  for_each = local.platform_controllers

  name = "${local.project}-${local.environment}-pi-${each.key}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = merge(local.common_tags, {
    Name      = "${local.project}-${local.environment}-pi-${each.key}"
    Component = each.key
  })
}

resource "aws_iam_role_policy" "platform_inline" {
  for_each = { for k, v in local.platform_controllers : k => v if v.inline_policy != null }

  name   = "${local.project}-${local.environment}-${each.key}"
  role   = aws_iam_role.platform[each.key].id
  policy = each.value.inline_policy
}

resource "aws_iam_role_policy_attachment" "platform_managed" {
  for_each = local.platform_managed_attachments

  role       = aws_iam_role.platform[each.value.controller].name
  policy_arn = each.value.policy_arn
}

###############################################################################
# Pod Identity associations (SA → role) on the EKS cluster
###############################################################################
resource "aws_eks_pod_identity_association" "platform" {
  for_each = local.platform_controllers

  cluster_name    = module.eks.cluster_name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = aws_iam_role.platform[each.key].arn

  tags = merge(local.common_tags, {
    Name      = "${local.project}-${local.environment}-pi-${each.key}"
    Component = each.key
  })
}

###############################################################################
# Inputs
###############################################################################
variable "platform_secrets" {
  description = "Secrets to provision in AWS Secrets Manager for the platform"
  type = map(object({
    description             = optional(string, "")
    generate                = optional(bool, false)
    length                  = optional(number, 24)
    special                 = optional(bool, true)
    username                = optional(string)
    secret_string           = optional(string)
    recovery_window_in_days = optional(number, 7)
  }))
  default = {}
}

###############################################################################
# Outputs
###############################################################################
output "platform_secret_arns" {
  description = "Map of platform secret key → Secrets Manager ARN"
  value       = module.secrets.secret_arns
}

output "platform_secret_names" {
  description = "Map of platform secret key → Secrets Manager name"
  value       = module.secrets.secret_names
}

output "platform_pod_identity_role_arns" {
  description = "Map of platform controller → Pod Identity IAM role ARN"
  value       = { for k, r in aws_iam_role.platform : k => r.arn }
}
