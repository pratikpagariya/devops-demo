#!/usr/bin/env bash
###############################################################################
# bootstrap-secrets.sh — ALTERNATIVE to External Secrets.
#
# Pulls secrets straight from AWS Secrets Manager and creates the equivalent
# Kubernetes Secrets imperatively. Use this only if you are NOT running the
# External Secrets Operator (setup-all.sh uses ESO by default).
#
# Usage: ./bootstrap-secrets.sh [ENV]
###############################################################################
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

ENV="${1:-dev}"
PROJECT="devops-demo"
REGION="us-east-1"
for c in kubectl aws jq; do require_cmd "$c"; done

# get_json <secret-suffix>  → prints the JSON secret string
get_json() {
  aws secretsmanager get-secret-value --region "$REGION" \
    --secret-id "${PROJECT}-${ENV}-$1" --query SecretString --output text
}

ensure_ns() { kubectl get ns "$1" >/dev/null 2>&1 || kubectl create ns "$1"; }

log "Creating Kubernetes secrets from AWS Secrets Manager (${PROJECT}-${ENV}-*)"

ensure_ns jenkins
J="$(get_json jenkins-admin)"
kubectl -n jenkins create secret generic jenkins-admin \
  --from-literal=username="$(jq -r .username <<<"$J")" \
  --from-literal=password="$(jq -r .password <<<"$J")" \
  --dry-run=client -o yaml | kubectl apply -f -

ensure_ns monitoring
G="$(get_json grafana-admin)"
kubectl -n monitoring create secret generic grafana-admin \
  --from-literal=username="$(jq -r .username <<<"$G")" \
  --from-literal=password="$(jq -r .password <<<"$G")" \
  --dry-run=client -o yaml | kubectl apply -f -

ensure_ns sonarqube
S="$(get_json sonarqube-db)"
kubectl -n sonarqube create secret generic sonarqube-db \
  --from-literal=username="$(jq -r .username <<<"$S")" \
  --from-literal=password="$(jq -r .password <<<"$S")" \
  --dry-run=client -o yaml | kubectl apply -f -

M="$(get_json sonarqube-monitoring)"
kubectl -n sonarqube create secret generic sonarqube-monitoring \
  --from-literal=password="$(jq -r .password <<<"$M")" \
  --dry-run=client -o yaml | kubectl apply -f -

ok "Secrets created. (Run setup-all.sh WITHOUT the External Secrets steps if using this path.)"
