# deployment-configs — CI/CD & Platform Layer

Everything that runs **inside** the EKS cluster: CI/CD, GitOps, observability,
ingress, autoscaling, and the secrets plumbing that feeds them. The cluster
itself (VPC, EKS, ECR, IAM, Secrets Manager) is provisioned by [`../iac`](../iac).

```
deployment-configs/
├── helmcharts/        # chart catalogue (repos + pinned versions)
├── helmvalues/        # one values file per component
├── k8s-manifests/     # namespaces, StorageClass, SecretStore, ExternalSecrets,
│                      #   ALB ingresses, ArgoCD app-of-apps
├── jenkins/           # JCasC, plugin list, sample Jenkinsfiles
├── jobdsl/            # Job DSL seed + per-microservice pipeline generators
└── scripts/           # setup-all.sh (installer), bootstrap-secrets.sh, uninstall-all.sh
```

## Components installed

| Layer | Component | Namespace | IAM (Pod Identity) |
|-------|-----------|-----------|--------------------|
| Controllers | metrics-server | kube-system | — |
| | AWS Load Balancer Controller | kube-system | ✅ alb policy |
| | Cluster Autoscaler | kube-system | ✅ autoscaling |
| | EBS CSI driver (EKS addon, via Terraform) | kube-system | ✅ AmazonEBSCSIDriverPolicy |
| Secrets | External Secrets Operator | external-secrets | ✅ secretsmanager:GetSecretValue |
| CI/CD | Argo CD | argocd | — |
| | Jenkins | jenkins | ✅ ECR push |
| | SonarQube (Community) | sonarqube | — |
| Observability | kube-prometheus-stack (Prometheus, Grafana, Alertmanager) | monitoring | — |
| | Loki + Promtail | monitoring | — |

## Architecture

```
                         ┌─────────────── AWS ───────────────┐
   AWS Secrets Manager ──┤  devops-demo-dev-*  (Terraform)   │
            │            └───────────────────────────────────┘
            │ Pod Identity (external-secrets SA)
            ▼
   ┌─────────────────────── EKS cluster ───────────────────────┐
   │  External Secrets Operator → Kubernetes Secrets            │
   │        │                                                   │
   │        ├── jenkins-admin → Jenkins ─┐                      │
   │        ├── grafana-admin → Grafana  │ build → SonarQube    │
   │        ├── sonarqube-* → SonarQube  │      → Kaniko → ECR  │
   │        └── git/registry/sonar token │      → Git bump      │
   │                                     ▼                      │
   │   Argo CD  ◄── watches Git ── App-of-Apps ── deploys apps  │
   │                                                            │
   │   Prometheus ── scrapes ──► all pods                       │
   │   Promtail ── ships logs ──► Loki ──► Grafana datasource   │
   │                                                            │
   │   AWS LB Controller ── one ALB ──► argocd/jenkins/         │
   │                                    grafana/sonarqube       │
   └────────────────────────────────────────────────────────────┘
```

## Prerequisites

1. The `iac/` dev stack is applied (EKS up; `eks-pod-identity-agent` and
   `aws-ebs-csi-driver` addons present; Pod Identity associations + Secrets
   Manager secrets created by `platform.tf` / `module.secrets`).
2. Tools on your machine: `kubectl`, `helm`, `aws`, `jq`.

## Install

```bash
cd deployment-configs/scripts
./setup-all.sh dev
```

The script: connects kubeconfig → adds Helm repos → applies namespaces +
default gp3 StorageClass → installs controllers → installs External Secrets and
**waits** for the synced credentials → installs CI/CD + observability →
applies ALB ingresses → applies the ArgoCD App-of-Apps. It is idempotent
(`helm upgrade --install`), so re-running is safe.

## Credentials (all from AWS Secrets Manager)

No password is hardcoded. Terraform generates them into Secrets Manager; the
External Secrets Operator syncs them into Kubernetes; Helm charts consume them
via `existingSecret`.

```bash
# Jenkins / Grafana admin password
aws secretsmanager get-secret-value --secret-id devops-demo-dev-jenkins-admin \
  --query SecretString --output text | jq -r .password

# ArgoCD initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

Placeholder secrets you must update in Secrets Manager with real values:
`devops-demo-dev-git-credentials`, `-registry-credentials`, `-sonarqube-token`.

## Before production

- **DNS + TLS**: ingresses use `*.dev.example.com` and share one ALB
  (`group.name=devops-demo-dev`). Point Route53 records at the ALB and add your
  ACM `certificate-arn` to each ingress annotation.
- **Chart versions** in `helmcharts/charts.yaml` / `setup-all.sh` are pinned —
  verify with `helm search repo <repo>/<chart> --versions` and bump together.
- **ALB IAM policy** (`iac/stacks/dev/policies/aws-load-balancer-controller.json`)
  should be diffed against the upstream policy for your controller version.
- **Loki** runs in SingleBinary/filesystem mode (dev). Switch to S3 +
  SimpleScalable for prod.
- **Job DSL script security** is disabled for convenience — enable it and approve
  scripts for a real Jenkins.

## Teardown

```bash
./uninstall-all.sh dev      # removes Helm releases + manifests (not the cluster)
```
