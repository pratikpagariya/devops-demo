#!/usr/bin/env bash
###############################################################################
# destroy.sh — Destroy a Terraform stack
#
# Usage:
#   ./destroy.sh <ENV> [--auto-approve]
###############################################################################
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

ENV="${1:-}"
AUTO_APPROVE=false

[[ -z "$ENV" ]] && die "Usage: $0 <ENV> [--auto-approve]"
shift
for arg in "$@"; do
  [[ "$arg" == "--auto-approve" ]] && AUTO_APPROVE=true
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IAC_DIR="$(dirname "$SCRIPT_DIR")"
STACK_DIR="$IAC_DIR/stacks/$ENV"
PROJECT="devops-demo"
REGION="us-east-1"

[[ -d "$STACK_DIR" ]] || die "Stack directory not found: $STACK_DIR"
command -v terraform >/dev/null || die "terraform not found"
command -v aws       >/dev/null || die "aws-cli not found"

[[ -n "${TF_VAR_rds_db_password:-}" ]] || \
  die "TF_VAR_rds_db_password must be set"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
STATE_BUCKET="${PROJECT}-tfstate-${ACCOUNT_ID}"
STATE_KEY="${ENV}/terraform.tfstate"

warn "========================================================"
warn "  You are about to DESTROY the '$ENV' environment!"
warn "========================================================"
echo ""

if [[ "$AUTO_APPROVE" != "true" ]]; then
  read -r -p "Type the environment name to confirm destruction: " CONFIRM
  [[ "$CONFIRM" == "$ENV" ]] || { warn "Confirmation mismatch. Aborted."; exit 0; }
fi

log "Initializing..."
terraform -chdir="$STACK_DIR" init -upgrade -reconfigure \
  -backend-config="bucket=$STATE_BUCKET" \
  -backend-config="key=$STATE_KEY" \
  -backend-config="region=$REGION" \
  -backend-config="use_lockfile=true" \
  -backend-config="encrypt=true"

log "Destroying stack: $ENV"
DESTROY_ARGS="-var-file=../../params/${ENV}.tfvars"
[[ "$AUTO_APPROVE" == "true" ]] && DESTROY_ARGS="$DESTROY_ARGS -auto-approve"

# shellcheck disable=SC2086
terraform -chdir="$STACK_DIR" destroy $DESTROY_ARGS

ok "Destroy complete for environment: $ENV"
