###############################################################################
# Secrets Manager Module — main.tf
# Generic, reusable module. Driven by a map(object) + for_each.
#
# Each secret can either:
#   - store an explicit value (secret_string), OR
#   - auto-generate a random password (generate = true), optionally wrapped
#     as JSON { "username": ..., "password": ... } when username is set, OR
#   - be created empty (no version) so an operator/app sets the value later.
###############################################################################

locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = merge(var.tags, {
    Module = "secrets"
  })

  # Secrets that need a generated password (generate=true and no explicit value)
  generated = {
    for k, v in var.secrets : k => v
    if v.generate && v.secret_string == null
  }

  # Secrets that have a value to store (explicit OR generated)
  with_version = {
    for k, v in var.secrets : k => v
    if v.secret_string != null || v.generate
  }
}

###############################################################################
# Random passwords (only for generate=true without explicit value)
###############################################################################
resource "random_password" "this" {
  for_each = local.generated

  length           = each.value.length
  special          = each.value.special
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

###############################################################################
# Secret containers
###############################################################################
resource "aws_secretsmanager_secret" "this" {
  for_each = var.secrets

  name                    = "${local.name_prefix}-${each.key}"
  description             = each.value.description
  recovery_window_in_days = each.value.recovery_window_in_days
  kms_key_id              = var.kms_key_id

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-${each.key}"
    Secret = each.key
  })
}

###############################################################################
# Secret values
###############################################################################
resource "aws_secretsmanager_secret_version" "this" {
  for_each = local.with_version

  secret_id = aws_secretsmanager_secret.this[each.key].id

  secret_string = each.value.secret_string != null ? each.value.secret_string : (
    each.value.username != null
    ? jsonencode({ username = each.value.username, password = random_password.this[each.key].result })
    : jsonencode({ password = random_password.this[each.key].result })
  )

  lifecycle {
    # Allow values to be rotated out-of-band without Terraform reverting them.
    ignore_changes = [secret_string]
  }
}
