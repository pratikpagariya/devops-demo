#!/usr/bin/env bash
###############################################################################
# apply.sh — Deploy a Terraform stack
#
# Usage:
#   ./apply.sh <ENV> [--auto-approve] [--plan-only]
#
# Examples:
#   ./apply.sh dev
#   ./apply.sh prod --auto-approve
#   ./apply.sh dev --plan-only
###############################################################################
set -euo pipefail

###############################################################################
# Helpers
###############################################################################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

###############################################################################
# Parse arguments
###############################################################################
ENV="${1:-}"
AUTO_APPROVE=false
PLAN_ONLY=false

[[ -z "$ENV" ]] && die "Usage: $0 <ENV> [--auto-approve] [--plan-only]"

shift
for arg in "$@"; do
  case "$arg" in
    --auto-approve) AUTO_APPROVE=true ;;
    --plan-only)    PLAN_ONLY=true ;;
    *) die "Unknown argument: $arg" ;;
  esac
done

###############################################################################
# Config
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IAC_DIR="$(dirname "$SCRIPT_DIR")"
STACK_DIR="$IAC_DIR/stacks/$ENV"
PARAMS_FILE="$IAC_DIR/params/${ENV}.tfvars"
PROJECT="devops-demo"
REGION="us-east-1"

###############################################################################
# Validation
###############################################################################
[[ -d "$STACK_DIR" ]]  || die "Stack directory not found: $STACK_DIR"
[[ -f "$PARAMS_FILE" ]] || die "Params file not found: $PARAMS_FILE"

command -v terraform >/dev/null 2>&1 || die "terraform not found in PATH"
command -v aws       >/dev/null 2>&1 || die "aws-cli not found in PATH"

# Check AWS credentials
aws sts get-caller-identity --region "$REGION" >/dev/null 2>&1 || \
  die "AWS credentials invalid or missing. Run: aws configure"

# Require DB password in env (never in tfvars)
[[ -n "${TF_VAR_rds_db_password:-}" ]] || \
  die "TF_VAR_rds_db_password must be set. Example: export TF_VAR_rds_db_password=<secret>"

###############################################################################
# Resolve backend config from bootstrap outputs
###############################################################################
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
STATE_BUCKET="${PROJECT}-tfstate-${ACCOUNT_ID}"
STATE_KEY="${ENV}/terraform.tfstate"

log "Stack:   $ENV"
log "Region:  $REGION"
log "Bucket:  $STATE_BUCKET"
log "Key:     $STATE_KEY"
log "Lock:    S3 native (use_lockfile)"
echo ""

###############################################################################
# Bootstrap backend if bucket does not exist
###############################################################################
if ! aws s3api head-bucket --bucket "$STATE_BUCKET" --region "$REGION" 2>/dev/null; then
  warn "State bucket not found. Bootstrapping backend..."
  pushd "$IAC_DIR/backend" >/dev/null
    terraform init -upgrade
    terraform apply \
      -var="project=$PROJECT" \
      -var="region=$REGION" \
      -auto-approve
  popd >/dev/null
  ok "Backend bootstrapped."
fi

###############################################################################
# Terraform init
###############################################################################
log "Running terraform init..."
terraform -chdir="$STACK_DIR" init -upgrade -reconfigure \
  -backend-config="bucket=$STATE_BUCKET" \
  -backend-config="key=$STATE_KEY" \
  -backend-config="region=$REGION" \
  -backend-config="use_lockfile=true" \
  -backend-config="encrypt=true"

###############################################################################
# Terraform validate
###############################################################################
log "Validating configuration..."
terraform -chdir="$STACK_DIR" validate
ok "Validation passed."

###############################################################################
# Terraform plan
###############################################################################
PLAN_FILE="$IAC_DIR/.terraform-plan-${ENV}.tfplan"
log "Running terraform plan..."
terraform -chdir="$STACK_DIR" plan \
  -var-file="../../params/${ENV}.tfvars" \
  -out="$PLAN_FILE"

if [[ "$PLAN_ONLY" == "true" ]]; then
  ok "Plan complete (--plan-only; skipping apply)."
  exit 0
fi

###############################################################################
# Terraform apply
###############################################################################
if [[ "$AUTO_APPROVE" == "true" ]]; then
  log "Applying with --auto-approve..."
  terraform -chdir="$STACK_DIR" apply "$PLAN_FILE"
else
  echo ""
  read -r -p "Apply the plan to '$ENV'? [yes/no]: " CONFIRM
  [[ "$CONFIRM" == "yes" ]] || { warn "Aborted."; exit 0; }
  terraform -chdir="$STACK_DIR" apply "$PLAN_FILE"
fi

ok "Apply complete for environment: $ENV"

###############################################################################
# Post-apply: update kubeconfig
###############################################################################
CLUSTER_NAME="${PROJECT}-${ENV}-eks"
log "Fetching kubeconfig for cluster: $CLUSTER_NAME"

if aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" >/dev/null 2>&1; then
  aws eks update-kubeconfig \
    --region "$REGION" \
    --name   "$CLUSTER_NAME" \
    --alias  "$CLUSTER_NAME"
  ok "kubeconfig updated. Active context: $CLUSTER_NAME"
else
  warn "Cluster '$CLUSTER_NAME' not yet ready or not found; skipping kubeconfig update."
fi

echo ""
ok "Done! Summary of outputs:"
terraform -chdir="$STACK_DIR" output
