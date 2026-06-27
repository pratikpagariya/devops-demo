#!/usr/bin/env bash
###############################################################################
# uninstall-all.sh — FULL clean slate so you can re-run setup-all.sh fresh.
#
# Removes (in safe order):
#   ArgoCD Applications (finalizers cleared) -> ingresses (so the ALB is freed)
#   -> ExternalSecrets -> all Helm releases -> all platform PVCs (DATA LOSS).
#
# Does NOT touch: the EKS cluster, IAM, the EBS CSI addon, the pre-baked Jenkins
# ECR image, or AWS Secrets Manager — those are Terraform-managed and reused.
#
# Usage: ./uninstall-all.sh [ENV]
###############################################################################
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DC_DIR="$(dirname "$SCRIPT_DIR")"
MANIFESTS="$DC_DIR/k8s-manifests"
source "$SCRIPT_DIR/lib/common.sh"

ENV="${1:-dev}"
for c in kubectl helm; do require_cmd "$c"; done

warn "============================================================"
warn " FULL TEARDOWN of the in-cluster platform (env: $ENV)."
warn " Deletes Helm releases, the ALB, and ALL platform PVCs"
warn " (Jenkins / SonarQube / Prometheus / Grafana / Loki data is lost)."
warn " EKS cluster, IAM, ECR image, and Secrets Manager are untouched."
warn "============================================================"
read -r -p "Type 'yes' to continue: " CONFIRM
[[ "$CONFIRM" == "yes" ]] || { warn "Aborted."; exit 0; }

###############################################################################
# 1. ArgoCD Applications first — clear finalizers so they don't hang once the
#    ArgoCD controller is gone.
###############################################################################
log "Removing ArgoCD Applications..."
kubectl delete -f "$MANIFESTS/argocd-apps/app-of-apps.yaml" --ignore-not-found --timeout=60s 2>/dev/null || true
kubectl -n argocd delete applications --all --ignore-not-found --timeout=60s 2>/dev/null || true
for app in $(kubectl -n argocd get applications -o name 2>/dev/null || true); do
  kubectl -n argocd patch "$app" --type=merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
done

###############################################################################
# 2. Ingresses — delete BEFORE the ALB controller so the ALB is cleaned up.
###############################################################################
log "Removing ingresses (frees the ALB)..."
kubectl delete -f "$MANIFESTS/ingress/" --ignore-not-found 2>/dev/null || true

###############################################################################
# 3. External Secrets resources
###############################################################################
log "Removing ExternalSecrets + ClusterSecretStore..."
kubectl delete -f "$MANIFESTS/external-secrets/externalsecrets.yaml" --ignore-not-found 2>/dev/null || true
kubectl delete -f "$MANIFESTS/secret-store.yaml" --ignore-not-found 2>/dev/null || true

# SonarQube's external PostgreSQL (Deployment + Service + PVC)
kubectl delete -f "$MANIFESTS/sonarqube-postgres.yaml" --ignore-not-found 2>/dev/null || true

###############################################################################
# 4. Helm releases (reverse of install order)
###############################################################################
uninstall() { helm uninstall "$1" -n "$2" 2>/dev/null && ok "removed $1" || warn "$1 not present"; }
log "Uninstalling Helm releases..."
uninstall promtail monitoring
uninstall loki monitoring
uninstall kube-prometheus-stack monitoring
uninstall sonarqube sonarqube
uninstall jenkins jenkins
uninstall argocd argocd
uninstall external-secrets external-secrets
uninstall cluster-autoscaler kube-system
uninstall aws-load-balancer-controller kube-system
uninstall metrics-server kube-system

###############################################################################
# 5. PVCs — clean slate for the stateful apps (waits for pods to release them).
###############################################################################
log "Deleting platform PVCs..."
for ns in monitoring jenkins sonarqube; do
  kubectl -n "$ns" delete pvc --all --ignore-not-found 2>/dev/null || true
done

ok "Teardown complete — you can now re-run:  ./setup-all.sh $ENV"
echo ""
echo "Notes:"
echo "  - The pre-baked Jenkins ECR image is kept (setup-all reuses it; no rebuild)."
echo "  - Namespaces are left in place (setup-all re-applies them idempotently)."
echo "    For an even deeper clean you can also run:"
echo "      kubectl delete ns argocd jenkins sonarqube monitoring external-secrets app"
