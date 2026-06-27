pwd#!/usr/bin/env bash
###############################################################################
# setup-all.sh — install the entire CI/CD + platform stack into the EKS cluster.
#
# Usage:
#   ./setup-all.sh [ENV]          # ENV defaults to "dev"
#
# Prereqs (must already exist):
#   - EKS cluster deployed by iac/ (with eks-pod-identity-agent + EBS CSI addons)
#   - AWS Secrets Manager secrets created by iac (module.secrets)
#   - Tools: kubectl, helm, aws, jq
#
# Order is deliberate:
#   controllers → External Secrets → (secrets sync) → CI/CD + observability →
#   ingress → ArgoCD app-of-apps
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DC_DIR="$(dirname "$SCRIPT_DIR")"                 # deployment-configs/
REPO_ROOT="$(dirname "$DC_DIR")"                  # repo root
VALUES="$DC_DIR/helmvalues"
MANIFESTS="$DC_DIR/k8s-manifests"

source "$SCRIPT_DIR/lib/common.sh"

ENV="${1:-dev}"
PROJECT="devops-demo"
REGION="us-east-1"
CLUSTER_NAME="${PROJECT}-${ENV}-eks"

# ---- Pinned chart versions (keep in sync with helmcharts/charts.yaml) -------
V_METRICS_SERVER="3.12.2"
V_ALB="1.9.2"
V_AUTOSCALER="9.43.2"
V_EXTERNAL_SECRETS="0.10.7"
V_ARGOCD="7.7.7"
V_JENKINS="5.8.16"
V_SONARQUBE="10.7.0"
V_KPS="65.5.1"
V_LOKI="6.18.0"
V_PROMTAIL="6.16.6"

###############################################################################
# Ensure the pre-baked Jenkins image exists in ECR (build + push if missing).
# Plugins are baked in at build time, so the pod downloads NOTHING at startup —
# this is what prevents the boot-time "HTTP 503 plugin download" crashloop.
# Idempotent: builds only on first run; reuses the ECR image afterwards.
###############################################################################
ensure_jenkins_image() {
  log "Checking pre-baked Jenkins image: $ECR/$JENKINS_IMAGE_REPO:$JENKINS_IMAGE_TAG"
  aws ecr describe-repositories --repository-names "$JENKINS_IMAGE_REPO" --region "$REGION" >/dev/null 2>&1 \
    || aws ecr create-repository --repository-name "$JENKINS_IMAGE_REPO" --region "$REGION" >/dev/null
  if aws ecr describe-images --repository-name "$JENKINS_IMAGE_REPO" \
       --image-ids imageTag="$JENKINS_IMAGE_TAG" --region "$REGION" >/dev/null 2>&1; then
    ok "Jenkins image already in ECR — reusing it."
    return 0
  fi
  command -v docker >/dev/null 2>&1 || die "Jenkins image not in ECR and 'docker' is not installed here.
Build it once on any machine with Docker, then re-run this script:
  aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR
  docker build -t $ECR/$JENKINS_IMAGE_REPO:$JENKINS_IMAGE_TAG $DC_DIR/jenkins
  docker push  $ECR/$JENKINS_IMAGE_REPO:$JENKINS_IMAGE_TAG"
  log "Building + pushing pre-baked Jenkins image (first run only)..."
  aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ECR"
  docker build -t "$ECR/$JENKINS_IMAGE_REPO:$JENKINS_IMAGE_TAG" "$DC_DIR/jenkins"
  docker push "$ECR/$JENKINS_IMAGE_REPO:$JENKINS_IMAGE_TAG"
  ok "Jenkins image pushed."
}

###############################################################################
# 0. Preflight
###############################################################################
for c in kubectl helm aws jq; do require_cmd "$c"; done

log "Environment : $ENV"
log "Cluster     : $CLUSTER_NAME"
log "Region      : $REGION"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)" \
  || die "AWS credentials not configured."
export AWS_ACCOUNT_ID="$ACCOUNT_ID"

# ECR registry + the pre-baked Jenkins image (built/reused by ensure_jenkins_image)
ECR="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
JENKINS_IMAGE_REPO="${PROJECT}-${ENV}-jenkins"
JENKINS_IMAGE_TAG="2.504.1"

# Discover VPC id from Terraform outputs if available, else from AWS by tag.
VPC_ID="$(terraform -chdir="$REPO_ROOT/iac/stacks/$ENV" output -raw vpc_id 2>/dev/null || true)"
if [[ -z "$VPC_ID" ]]; then
  VPC_ID="$(aws ec2 describe-vpcs --region "$REGION" \
    --filters "Name=tag:Name,Values=${PROJECT}-${ENV}-vpc" \
    --query 'Vpcs[0].VpcId' --output text 2>/dev/null || true)"
fi
[[ -n "$VPC_ID" && "$VPC_ID" != "None" ]] || die "Could not determine VPC ID."
log "VPC ID      : $VPC_ID"

log "Updating kubeconfig..."
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" >/dev/null
kubectl cluster-info >/dev/null || die "Cannot reach cluster $CLUSTER_NAME"
ok "Connected to $CLUSTER_NAME"

###############################################################################
# 1. Helm repositories
###############################################################################
log "Adding Helm repositories..."
helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1 || true
helm repo add autoscaler https://kubernetes.github.io/autoscaler >/dev/null 2>&1 || true
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ >/dev/null 2>&1 || true
helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1 || true
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo add jenkins https://charts.jenkins.io >/dev/null 2>&1 || true
helm repo add sonarqube https://SonarSource.github.io/helm-chart-sonarqube >/dev/null 2>&1 || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null
ok "Helm repos ready."

###############################################################################
# 2. Namespaces + default gp3 StorageClass
###############################################################################
kubectl apply -f "$MANIFESTS/namespaces.yaml"
kubectl apply -f "$MANIFESTS/storageclass-gp3.yaml"
# Demote any legacy gp2 default so gp3 is the single default.
if kubectl get sc gp2 >/dev/null 2>&1; then
  kubectl patch storageclass gp2 \
    -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' >/dev/null || true
fi
ok "Namespaces + StorageClass applied."

###############################################################################
# 3. Cluster controllers
###############################################################################
helm_install metrics-server metrics-server/metrics-server "$V_METRICS_SERVER" \
  kube-system "$VALUES/metrics-server.values.yaml"

helm_install aws-load-balancer-controller eks/aws-load-balancer-controller "$V_ALB" \
  kube-system "$VALUES/aws-load-balancer-controller.values.yaml" \
  --set clusterName="$CLUSTER_NAME" --set region="$REGION" --set vpcId="$VPC_ID"

helm_install cluster-autoscaler autoscaler/cluster-autoscaler "$V_AUTOSCALER" \
  kube-system "$VALUES/cluster-autoscaler.values.yaml" \
  --set autoDiscovery.clusterName="$CLUSTER_NAME" --set awsRegion="$REGION"

###############################################################################
# 4. External Secrets — then sync credentials from AWS Secrets Manager
###############################################################################
helm_install external-secrets external-secrets/external-secrets "$V_EXTERNAL_SECRETS" \
  external-secrets "$VALUES/external-secrets.values.yaml"

log "Applying ClusterSecretStore + ExternalSecrets..."
kubectl apply -f "$MANIFESTS/secret-store.yaml"
kubectl apply -f "$MANIFESTS/external-secrets/externalsecrets.yaml"

# Block until the credentials the apps need actually exist.
wait_for_secret jenkins   jenkins-admin
wait_for_secret monitoring grafana-admin
wait_for_secret sonarqube sonarqube-db
wait_for_secret sonarqube sonarqube-monitoring

###############################################################################
# 5. CI/CD
###############################################################################
helm_install argocd argo/argo-cd "$V_ARGOCD" \
  argocd "$VALUES/argocd.values.yaml"

# Jenkins runs a pre-baked image (plugins baked in → no boot-time downloads).
ensure_jenkins_image
helm_install jenkins jenkins/jenkins "$V_JENKINS" \
  jenkins "$VALUES/jenkins.values.yaml" \
  --set controller.image.registry="$ECR" \
  --set controller.image.repository="$JENKINS_IMAGE_REPO" \
  --set controller.image.tag="$JENKINS_IMAGE_TAG"

# SonarQube uses our own PostgreSQL (official image) — the chart's bundled
# Bitnami DB image was removed from Docker Hub. Deploy the DB first and wait.
kubectl apply -f "$MANIFESTS/sonarqube-postgres.yaml"
kubectl -n sonarqube rollout status deploy/sonar-postgres --timeout=180s
helm_install sonarqube sonarqube/sonarqube "$V_SONARQUBE" \
  sonarqube "$VALUES/sonarqube.values.yaml"

###############################################################################
# 6. Observability
###############################################################################
helm_install kube-prometheus-stack prometheus-community/kube-prometheus-stack "$V_KPS" \
  monitoring "$VALUES/kube-prometheus-stack.values.yaml"

helm_install loki grafana/loki "$V_LOKI" \
  monitoring "$VALUES/loki.values.yaml"

helm_install promtail grafana/promtail "$V_PROMTAIL" \
  monitoring "$VALUES/promtail.values.yaml"

###############################################################################
# 7. Ingress (ALB) + ArgoCD app-of-apps
###############################################################################
log "Applying ingresses..."
kubectl apply -f "$MANIFESTS/ingress/"
log "Applying ArgoCD App-of-Apps..."
kubectl apply -f "$MANIFESTS/argocd-apps/app-of-apps.yaml"

###############################################################################
# Done
###############################################################################
ok "Platform installed."
cat <<EOF

────────────────────────────────────────────────────────────────────────────
 Access
────────────────────────────────────────────────────────────────────────────
 ALB DNS (all UIs share one ALB):
   kubectl get ingress -A

 Credentials:
   Jenkins  admin pwd : aws secretsmanager get-secret-value --secret-id ${PROJECT}-${ENV}-jenkins-admin --query SecretString --output text | jq -r .password
   Grafana  admin pwd : aws secretsmanager get-secret-value --secret-id ${PROJECT}-${ENV}-grafana-admin --query SecretString --output text | jq -r .password
   ArgoCD   admin pwd : kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
   SonarQube          : admin / admin  (change on first login)

 Next:
   - Point DNS records (argocd/jenkins/grafana/sonarqube .dev.example.com) at the ALB.
   - Add the ACM certificate ARN to the ingress annotations for HTTPS.
   - Update placeholder secrets (git/registry/sonar token) in Secrets Manager.
────────────────────────────────────────────────────────────────────────────
EOF
