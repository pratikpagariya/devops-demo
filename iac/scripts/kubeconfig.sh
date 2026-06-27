#!/usr/bin/env bash
###############################################################################
# kubeconfig.sh — Refresh kubeconfig for an EKS cluster
#
# Usage:
#   ./kubeconfig.sh <ENV>
###############################################################################
set -euo pipefail

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()  { echo -e "${GREEN}[OK]${NC}    $*"; }
die() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

ENV="${1:-}"
[[ -z "$ENV" ]] && die "Usage: $0 <ENV>"

PROJECT="devops-demo"
REGION="us-east-1"
CLUSTER_NAME="${PROJECT}-${ENV}-eks"

command -v aws >/dev/null 2>&1 || die "aws-cli not found in PATH"

log "Verifying cluster exists: $CLUSTER_NAME"
aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$REGION" \
  --query "cluster.status" \
  --output text || die "Cluster not found: $CLUSTER_NAME"

log "Updating kubeconfig..."
aws eks update-kubeconfig \
  --region "$REGION" \
  --name   "$CLUSTER_NAME" \
  --alias  "$CLUSTER_NAME"

ok "kubeconfig updated. Current context set to: $CLUSTER_NAME"
kubectl config current-context
